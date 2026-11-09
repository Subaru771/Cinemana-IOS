export type ErrorCode =
  | 'AUTH_80045'
  | 'PAIRING_INVALID'
  | 'DEVICE_LOCKED'
  | 'DEVICE_DISCONNECTED'
  | 'DEVELOPER_MODE'
  | 'APP_LIMIT'
  | 'VERIFY_FAILED'
  | 'UNKNOWN';
export const ALL_CODES: ErrorCode[] = [
  'AUTH_80045', 'PAIRING_INVALID', 'DEVICE_LOCKED', 'DEVICE_DISCONNECTED',
  'DEVELOPER_MODE', 'APP_LIMIT', 'VERIFY_FAILED', 'UNKNOWN',
];
export class StepError extends Error {
  code: ErrorCode;
  constructor(code: ErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}
export function rawMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  try { return JSON.stringify(err); } catch { return String(err); }
}
const RULES: Array<[ErrorCode, RegExp]> = [
  ['AUTH_80045', /(?<!\d)-?80045(?!\d)|cannot be completed at this time/i],
  ['VERIFY_FAILED', /VERIFY_FAILED|did not report Cinemana SideStore/i],
  ['DEVICE_LOCKED', /PasswordProtected|device (is )?locked/i],
  ['PAIRING_INVALID', /InvalidHostID|UserDeniedPairing|PairingDialogResponsePending|invalid pairing|pairing (record|file)[^.]*(invalid|missing|corrupt|rejected)/i],
  ['DEVELOPER_MODE', /developer mode/i],
  ['APP_LIMIT', /maximum number of (apps|app ids)|reached the maximum/i],
  ['DEVICE_DISCONNECTED', /device (not found|disconnected)|no device|MUX_ERROR|usbmuxd/i],
];
export function classify(err: unknown): ErrorCode {
  if (err instanceof StepError) return err.code;
  const msg = rawMessage(err);
  for (const [code, re] of RULES) if (re.test(msg)) return code;
  return 'UNKNOWN';
}
