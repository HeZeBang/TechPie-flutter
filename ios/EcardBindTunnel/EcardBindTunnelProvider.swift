import Foundation
import Network
import NetworkExtension
import Darwin

/// A DNS-only packet tunnel. The sole included route is the virtual resolver's
/// /32; HTTPS and all other traffic keep using the device's ordinary network.
final class EcardBindTunnelProvider: NEPacketTunnelProvider {
    private let queue = DispatchQueue(label: "club.geekpie.techpie.ecard-bind-tunnel")
    private var active = false
    private var generation = 0
    private var pending: [UUID: NWConnection] = [:]
    private let maxPending = 8
    private let maxDNSPayload = 1472 // 1500-byte IPv4 packet minus IPv4/UDP headers.

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let config = proto.providerConfiguration,
              let host = config["host"] as? String,
              let ip = config["ip"] as? String,
              host == EcardBindDNS.host, ip == "119.78.254.196" else {
            completionHandler(tunnelError("Invalid eCard DNS configuration"))
            return
        }

        queue.async { [self] in
            guard !active else {
                completionHandler(nil)
                return
            }
            generation += 1
            let started = generation
            // Metadata only: this local tunnel has no remote VPN server. Keep
            // the endpoint distinct from the resolver's included route.
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.255"])
            ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "198.18.0.2",
                                                 subnetMask: "255.255.255.255")]
            settings.ipv4Settings = ipv4
            let dns = NEDNSSettings(servers: ["198.18.0.2"])
            // A supplemental resolver for this domain only, not the system's
            // default resolver. iOS also selects it for subdomains; those must
            // be relayed, never answered with the mirror address.
            dns.matchDomains = [EcardBindDNS.host]
            dns.matchDomainsNoSearch = true
            settings.dnsSettings = dns
            settings.mtu = NSNumber(value: 1500)
            setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self else {
                    completionHandler(error ?? Self.tunnelError("Tunnel stopped during setup"))
                    return
                }
                self.queue.async {
                    guard self.generation == started else {
                        completionHandler(Self.tunnelError("Tunnel stopped during setup"))
                        return
                    }
                    if let error {
                        completionHandler(error)
                        return
                    }
                    self.active = true
                    completionHandler(nil)
                    self.readNextBatch(generation: started)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async { [self] in
            generation += 1
            active = false
            let connections = Array(pending.values)
            pending.removeAll()
            for connection in connections { connection.cancel() }
            completionHandler()
        }
    }

    private func readNextBatch(generation: Int) {
        guard active, self.generation == generation else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.queue.async {
                guard self.active, self.generation == generation else { return }
                for (packet, family) in zip(packets, protocols) where family.int32Value == AF_INET {
                    self.handle(packet, generation: generation)
                }
                self.readNextBatch(generation: generation)
            }
        }
    }

    private func handle(_ packet: Data, generation: Int) {
        guard let datagram = EcardBindPackets.parseUDP(packet),
              datagram.destinationPort == EcardBindPackets.dnsPort,
              datagram.destination == EcardBindPackets.virtualDNS,
              let question = EcardBindDNS.parseQuestion(datagram.payload) else { return }

        if question.name == EcardBindDNS.host {
            let answer = question.type == EcardBindDNS.typeA && question.dnsClass == 1
                ? EcardBindPackets.mirror : nil
            respond(EcardBindDNS.reply(to: datagram.payload, question: question, address: answer),
                    to: datagram, generation: generation)
        } else {
            forward(datagram, question: question, generation: generation)
        }
    }

    private func respond(_ payload: Data?, to datagram: EcardBindPackets.Datagram, generation: Int) {
        guard active, self.generation == generation, let payload,
              let reply = EcardBindPackets.buildUDPReply(to: datagram, payload: payload) else { return }
        packetFlow.writePackets([reply], withProtocols: [NSNumber(value: AF_INET)])
    }

    /// Bounded upstream relay for any other name selected by the supplemental
    /// domain rule (including subdomains). The fixed upstream IP is not routed
    /// into this tunnel, so its UDP socket cannot recurse into packetFlow.
    private func forward(_ datagram: EcardBindPackets.Datagram,
                         question: EcardBindDNS.Question, generation: Int) {
        guard pending.count < maxPending, datagram.payload.count <= maxDNSPayload,
              let port = NWEndpoint.Port(rawValue: 53) else {
            respond(EcardBindDNS.reply(to: datagram.payload, question: question,
                                        rcode: EcardBindDNS.rcodeServerFailure),
                    to: datagram, generation: generation)
            return
        }
        let request = UUID()
        let connection = NWConnection(host: NWEndpoint.Host("1.1.1.1"), port: port, using: .udp)
        pending[request] = connection
        let query = datagram.payload
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.queue.async {
                    guard self.active, self.generation == generation,
                          self.pending[request] != nil else { return }
                    connection.send(content: query, completion: .contentProcessed { [weak self] error in
                        guard let self else { return }
                        if error != nil {
                            self.queue.async {
                                self.finish(request, response: nil, query: query, question: question,
                                            datagram: datagram, generation: generation)
                            }
                        }
                    })
                    connection.receiveMessage { [weak self] data, _, _, _ in
                        guard let self else { return }
                        self.queue.async {
                            self.finish(request, response: data, query: query, question: question,
                                        datagram: datagram, generation: generation)
                        }
                    }
                }
            case .failed:
                self.queue.async {
                    self.finish(request, response: nil, query: query, question: question,
                                datagram: datagram, generation: generation)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .milliseconds(1500)) { [weak self] in
            self?.finish(request, response: nil, query: query, question: question,
                         datagram: datagram, generation: generation)
        }
    }

    private func finish(_ request: UUID, response: Data?, query: Data,
                        question: EcardBindDNS.Question,
                        datagram: EcardBindPackets.Datagram, generation: Int) {
        guard let connection = pending.removeValue(forKey: request) else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        guard active, self.generation == generation else { return }
        // This local resolver serves UDP only. Do not advertise TCP fallback:
        // a retry to the virtual address would have nowhere to connect.
        if let response, EcardBindDNS.matchesResponse(response, to: query, question: question),
           response.count <= maxDNSPayload, response[response.startIndex + 2] & 0x02 == 0 {
            respond(response, to: datagram, generation: generation)
        } else {
            respond(EcardBindDNS.reply(to: query, question: question,
                                        rcode: EcardBindDNS.rcodeServerFailure),
                    to: datagram, generation: generation)
        }
    }

    private static func tunnelError(_ message: String) -> NSError {
        NSError(domain: "club.geekpie.techpie.EcardBindTunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func tunnelError(_ message: String) -> NSError { Self.tunnelError(message) }
}
