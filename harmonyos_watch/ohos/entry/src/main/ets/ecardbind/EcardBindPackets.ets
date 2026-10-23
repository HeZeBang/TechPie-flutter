/**
 * The little bit of IPv4/UDP the bind tunnel needs: recognise a DNS query taken
 * off the interface queue, and build the reply packet to put back into it.
 *
 * A socket on port 53 is not an option — port 53 is privileged, so binding to
 * it fails — while reading and writing the interface needs no privilege at all.
 * This is the same packet layout the Android service uses
 * (android/.../ecardbind/EcardBindPackets.kt), so both platforms answer with
 * identical bytes.
 */

const IPV4_HEADER: number = 20;
const UDP_HEADER: number = 8;
const VERSION_IPV4: number = 0x40;
const FRAGMENT_MASK: number = 0x3fff;
const DEFAULT_TTL: number = 64;
const FLAG_DONT_FRAGMENT: number = 0x4000;

export const UDP_PROTOCOL: number = 17;
export const DNS_PORT: number = 53;

/** A whole IPv4/UDP datagram, with its payload located in the packet. */
export interface EcardBindDatagram {
  sourceAddress: number[];
  destinationAddress: number[];
  sourcePort: number;
  destinationPort: number;
  identification: number;
  payloadOffset: number;
  payloadLength: number;
}

/** The UDP datagram inside `packet`, or null when it is not a whole IPv4 one. */
export function parseUdp(packet: Uint8Array, length: number): EcardBindDatagram | null {
  if (length < IPV4_HEADER) {
    return null;
  }
  if ((packet[0] & 0xf0) !== VERSION_IPV4) {
    return null;
  }
  const headerLength = (packet[0] & 0x0f) * 4;
  if (headerLength < IPV4_HEADER || headerLength + UDP_HEADER > length) {
    return null;
  }
  if (packet[9] !== UDP_PROTOCOL) {
    return null;
  }
  // Anything but a whole datagram (fragment offset, more fragments) is not a
  // DNS query; the resolver does not fragment them.
  const offsetAndFlags = (packet[6] << 8) | packet[7];
  if ((offsetAndFlags & FRAGMENT_MASK) !== 0) {
    return null;
  }
  const udpLength = (packet[headerLength + 4] << 8) | packet[headerLength + 5];
  if (udpLength < UDP_HEADER || headerLength + udpLength > length) {
    return null;
  }
  return {
    sourceAddress: [packet[12], packet[13], packet[14], packet[15]],
    destinationAddress: [packet[16], packet[17], packet[18], packet[19]],
    sourcePort: portAt(packet, headerLength),
    destinationPort: portAt(packet, headerLength + 2),
    identification: (packet[4] << 8) | packet[5],
    payloadOffset: headerLength + UDP_HEADER,
    payloadLength: udpLength - UDP_HEADER,
  };
}

/** An IPv4/UDP packet carrying `payload`, addressed back at `query`'s sender. */
export function buildUdpReply(query: EcardBindDatagram, payload: Uint8Array): Uint8Array {
  const totalLength = IPV4_HEADER + UDP_HEADER + payload.length;
  const packet = new Uint8Array(totalLength);
  packet[0] = VERSION_IPV4 | (IPV4_HEADER / 4);
  packet[2] = totalLength >> 8;
  packet[3] = totalLength;
  packet[4] = query.identification >> 8;
  packet[5] = query.identification;
  packet[6] = FLAG_DONT_FRAGMENT >> 8;
  packet[7] = FLAG_DONT_FRAGMENT;
  packet[8] = DEFAULT_TTL;
  packet[9] = UDP_PROTOCOL;
  // Bytes 10..11 stay zero until the header checksum is written.
  packet[12] = query.destinationAddress[0];
  packet[13] = query.destinationAddress[1];
  packet[14] = query.destinationAddress[2];
  packet[15] = query.destinationAddress[3];
  packet[16] = query.sourceAddress[0];
  packet[17] = query.sourceAddress[1];
  packet[18] = query.sourceAddress[2];
  packet[19] = query.sourceAddress[3];
  const headerChecksum = complement(sumWords(0, packet, 0, IPV4_HEADER));
  packet[10] = headerChecksum >> 8;
  packet[11] = headerChecksum;

  const udpLength = UDP_HEADER + payload.length;
  packet[IPV4_HEADER] = query.destinationPort >> 8;
  packet[IPV4_HEADER + 1] = query.destinationPort;
  packet[IPV4_HEADER + 2] = query.sourcePort >> 8;
  packet[IPV4_HEADER + 3] = query.sourcePort;
  packet[IPV4_HEADER + 4] = udpLength >> 8;
  packet[IPV4_HEADER + 5] = udpLength;
  packet.set(payload, IPV4_HEADER + UDP_HEADER);

  // Pseudo header: both addresses, then the zero byte and protocol as the word
  // 0x0011, then the UDP length.
  let running = sumWords(0, packet, 12, 8);
  running += UDP_PROTOCOL + udpLength;
  running += sumWords(0, packet, IPV4_HEADER, UDP_HEADER + payload.length);
  let udpChecksum = complement(running);
  // Zero means "not computed" for UDP, which some receivers reject.
  if (udpChecksum === 0) {
    udpChecksum = 0xffff;
  }
  packet[IPV4_HEADER + 6] = udpChecksum >> 8;
  packet[IPV4_HEADER + 7] = udpChecksum;
  return packet;
}

function portAt(packet: Uint8Array, offset: number): number {
  return (packet[offset] << 8) | packet[offset + 1];
}

function sumWords(initial: number, packet: Uint8Array, from: number, count: number): number {
  let total = initial;
  const end = from + count;
  let index = from;
  while (index + 1 < end) {
    total += (packet[index] << 8) | packet[index + 1];
    index += 2;
  }
  if (index < end) {
    total += packet[index] << 8;
  }
  return total;
}

function complement(sum: number): number {
  let folded = sum;
  while (folded > 0xffff) {
    folded = (folded >> 16) + (folded & 0xffff);
  }
  return (~folded) & 0xffff;
}
