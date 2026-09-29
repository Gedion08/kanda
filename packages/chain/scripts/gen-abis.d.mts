/** Types for gen-abis.mjs, so tests can call it safely. */
export declare const SOURCES: Readonly<Record<string, readonly [file: string, contract: string]>>;
export declare function readAbi(file: string, contract: string): unknown;
