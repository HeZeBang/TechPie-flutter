/**
 * The DNS wire format the bind tunnel speaks: echo the question, then either
 * append an A record pointing at the mirror or answer with no records at all so
 * the client falls back to IPv4.
 *
 * The layout — 0x8180 in the flags, a compressed name pointer 0xC00C for the
 * answer — is the one the Android service and the desktop hijack script already
 * serve the same records with.
 */

const HEADER_SIZE: number = 12;
const QUESTION_TAIL: number = 4;
const ANSWER_SIZE: number = 16;
const COMPRESSION_MASK: number = 0xc0;
const RESPONSE_FLAGS: number = 0x80;
const RECURSION_DESIRED: number = 0x01;
const TRUNCATED: number = 0x02;
const CLASS_IN: number = 1;
const TTL_SECONDS: number = 60;

export const TYPE_A: number = 1;
export const RCODE_SERVFAIL: number = 2;

/** The question of a DNS message, with where its type field sits. */
export interface EcardBindQuestion {
  name: string;
  type: number;
  typeOffset: number;
}

export function queryId(payload: Uint8Array): number {
  return (payload[0] << 8) | payload[1];
}

/** The question of a DNS message, or null when it is not one we can read. */
export function parseQuestion(payload: Uint8Array, length: number): EcardBindQuestion | null {
  let name = '';
  let offset = HEADER_SIZE;
  let terminated = false;
  while (offset < length) {
    const labelLength = payload[offset];
    if (labelLength === 0) {
      offset += 1;
      terminated = true;
      break;
    }
    // Compression pointers never appear in a question.
    if ((labelLength & COMPRESSION_MASK) !== 0) {
      return null;
    }
    if (offset + 1 + labelLength > length) {
      return null;
    }
    if (name.length > 0) {
      name += '.';
    }
    for (let index = 0; index < labelLength; index++) {
      name += String.fromCharCode(payload[offset + 1 + index]);
    }
    offset += 1 + labelLength;
  }
  if (!terminated || offset + QUESTION_TAIL > length) {
    return null;
  }
  const type = (payload[offset] << 8) | payload[offset + 1];
  return { name: name, type: type, typeOffset: offset };
}

/**
 * The reply for `question`: the question echoed back, and — when `address` is
 * given — a single A record pointing at it. A null address answers with no
 * records at all, which is how the other types for the hijacked name are told to
 * use the A record instead; `rcode` other than 0 is a failure answer.
 */
export function buildReply(
  id: number,
  payload: Uint8Array,
  question: EcardBindQuestion,
  address: number[] | null,
  rcode: number = 0,
  truncated: boolean = false,
): Uint8Array {
  const questionLength = question.typeOffset + QUESTION_TAIL - HEADER_SIZE;
  const reply = new Uint8Array(
    HEADER_SIZE + questionLength + (address === null ? 0 : ANSWER_SIZE),
  );
  reply[0] = id >> 8;
  reply[1] = id;
  // Response, recursion available, and the query's own RD bit echoed back: a
  // resolver that asked for recursion is entitled to see it mirrored.
  reply[2] = RESPONSE_FLAGS | (payload[2] & RECURSION_DESIRED) | (truncated ? TRUNCATED : 0);
  reply[3] = RESPONSE_FLAGS | rcode;
  // One question, one answer at most, and no authority or additional records.
  reply[5] = 1;
  if (address !== null) {
    reply[7] = 1;
  }
  reply.set(payload.subarray(HEADER_SIZE, HEADER_SIZE + questionLength), HEADER_SIZE);
  if (address === null) {
    return reply;
  }

  let offset = HEADER_SIZE + questionLength;
  reply[offset++] = 0xc0;
  reply[offset++] = 0x0c;
  reply[offset++] = 0;
  reply[offset++] = TYPE_A;
  reply[offset++] = 0;
  reply[offset++] = CLASS_IN;
  reply[offset++] = 0;
  reply[offset++] = 0;
  reply[offset++] = 0;
  reply[offset++] = TTL_SECONDS;
  reply[offset++] = 0;
  reply[offset++] = 4;
  reply[offset++] = address[0];
  reply[offset++] = address[1];
  reply[offset++] = address[2];
  reply[offset++] = address[3];
  return reply;
}
