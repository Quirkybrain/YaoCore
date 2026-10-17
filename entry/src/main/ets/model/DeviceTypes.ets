/*
 * YaoCore C-02 shared device enums.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.1
 */
export enum StateSource {
  SENSOR_PHYSICAL = 'sensor.physical',
  DEVICE_FEEDBACK = 'device.feedback',
  AUTOMATION_LOCAL = 'automation.local',
  APP_LAN = 'app.lan',
  APP_CLOUD = 'app.cloud'
}

export enum AcMode {
  AUTO = 'AUTO',
  COOL = 'COOL',
  HEAT = 'HEAT',
  DRY = 'DRY',
  FAN = 'FAN',
  ECO = 'ECO',
  SLEEP = 'SLEEP'
}

export enum TransportProfile {
  P_HMAC = 'P-HMAC',
  P_TLS_PIN = 'P-TLS-PIN',
  P_BLOCKED = 'P-BLOCKED'
}
