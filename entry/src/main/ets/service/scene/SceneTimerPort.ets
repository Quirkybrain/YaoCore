/*
 * YaoCore C-11 scene timer seam.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.1.4 (TimerPort consumption), §6.4
 *
 * Pure delay seam so SceneExecutor stays free of platform timers and host
 * tests can drive delayMs deterministically. The production adapter belongs to
 * the composition root, not to service/scene.
 */
export interface SceneTimerPort {
  delay(ms: number): Promise<void>;
}
