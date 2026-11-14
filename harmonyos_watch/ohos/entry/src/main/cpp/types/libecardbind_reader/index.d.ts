// Types for libecardbind_reader.so (the NAPI module in src/main/cpp).

/** Reads one packet per call, on the JS thread, until stopReading. */
export const startReading: (
  fd: number,
  onPacket: (data: ArrayBuffer) => void,
  onError: (message: string) => void
) => void;

/** Writes `length` bytes of `data` into the interface. 0, or -errno. */
export const writePacket: (fd: number, data: ArrayBuffer, length: number) => number;

/** Ends the loop. The fd itself is the caller's to destroy. */
export const stopReading: () => void;
