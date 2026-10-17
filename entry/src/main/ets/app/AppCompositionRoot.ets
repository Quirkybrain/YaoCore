/*
 * YaoCore C-28 AppCompositionRoot.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §2.4, §2.7, §2.8, §17.1.2, §17.4; DES-B-C28-API/SEAM
 *
 * Single composition root for the process. Every dependency is constructor
 * injected; there is no global singleton or service locator. AppContext holds
 * this instance and passes it to Index through LocalStorage.
 *
 * Production-only adapters are imported here. No Mock/ohosTest import and no
 * development-only branch exists in this file (SC-11; check_production_mock_exclusion).
 *
 * Initialization is idempotent while in flight. A failed attempt resets the
 * promise so StartupErrorView retry can start a fresh attempt (DES-B §17.3).
 */
import { bundleManager, common } from '@kit.AbilityKit';
import { AppError, AppErrors } from '../common/types/AppError';
import type { ClockPort, IdPort, LoggerPort, MetricsPort, RandomPort } from '../common/types/Ports';
import { AuthPolicy } from '../service/auth/AuthModels';
import { AuthService } from '../service/auth/AuthService';
import { BleProvisioningService } from '../service/ble/BleProvisioningService';
import { OhosBlePermissionGate, OhosBleTransport } from '../service/ble/adapters/OhosBleTransport';
import { AssetCloudCredentialStore } from '../service/cloud/CloudCredentialStore';
import { CloudCommandClient, CloudSendRetryPolicy } from '../service/cloud/CloudCommandClient';
import { CloudCompletionEvaluator } from '../service/cloud/CloudCompletionEvaluator';
import { RdbCloudConfigStore } from '../service/cloud/CloudConfigStore';
import { CloudService } from '../service/cloud/CloudService';
import { ShadowReader } from '../service/cloud/ShadowReader';
import { SystemTimerPort } from '../service/cloud/SystemTimerPort';
import { OhosCloudHttpTransport } from '../service/cloud/adapters/OhosCloudHttpTransport';
import { CryptoRandomSource } from '../service/crypto/CryptoRandomSource';
import { CryptoService } from '../service/crypto/CryptoService';
import { OhosCryptoProvider } from '../service/crypto/OhosCryptoProvider';
import { DeviceCommandRunner } from '../service/device/DeviceCommandRunner';
import { FamilyService } from '../service/family/FamilyService';
import { GatewayDiscoveryService } from '../service/gateway/GatewayDiscoveryService';
import { GatewayRequestPolicy } from '../service/gateway/GatewayRequestPolicy';
import { LocalGatewayService } from '../service/gateway/LocalGatewayService';
import { OhosHttpTransport } from '../service/gateway/adapters/OhosHttpTransport';
import { I18nService } from '../service/i18n/I18nService';
import { OhosLocaleApplier } from '../service/i18n/OhosLocaleApplier';
import { RawfileI18nLoader } from '../service/i18n/RawfileI18nLoader';
import { InviteService } from '../service/invite/InviteService';
import { InviteServiceAdapter } from '../service/invite/InviteServiceAdapter';
import { RoomService } from '../service/room/RoomService';
import { SceneService } from '../service/scene/SceneService';
import { ClockSkewTracker } from '../service/security/ClockSkewTracker';
import { NonceCache } from '../service/security/NonceCache';
import { RequestSigner } from '../service/security/RequestSigner';
import { ResponseVerifier } from '../service/security/ResponseVerifier';
import { AssetStoreSecretStore } from '../service/storage/AssetStoreSecretStore';
import { MigrationRegistry } from '../service/storage/MigrationRegistry';
import { PreferencesStoreAdapter } from '../service/storage/PreferencesStoreAdapter';
import { RdbStoreAdapter } from '../service/storage/RdbStoreAdapter';
import { SecretDraftStore } from '../service/storage/SecretDraftStore';
import { StorageService } from '../service/storage/StorageService';
import type { PreferencesStore } from '../service/storage/PreferencesStore';
import type { SecretDraftPort } from '../service/storage/SecretDraftPort';
import type { IBleProvisioningClient } from '../service/ble/BleProvisioningPorts';
import type { IGatewayClient } from '../service/gateway/GatewayTransportPorts';
import type { SceneTimerPort } from '../service/scene/SceneTimerPort';
import { DeviceRepository } from '../repository/DeviceRepository';
import { DomainMigrations } from '../repository/DomainMigrations';
import { DomainOperationGate } from '../repository/DomainOperationGate';
import { FamilyRepository } from '../repository/FamilyRepository';
import { GatewayRepository } from '../repository/GatewayRepository';
import { RoomRepository } from '../repository/RoomRepository';
import { SceneRepository } from '../repository/SceneRepository';
import { DeviceControlCoordinator } from '../viewmodel/core/DeviceControlCoordinator';
import type { VmTimerPort } from '../viewmodel/core/ViewModelCore';
import { BleProvisioningViewModel } from '../viewmodel/BleProvisioningViewModel';
import { ClimateViewModel } from '../viewmodel/ClimateViewModel';
import { DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { DoorViewModel } from '../viewmodel/DoorViewModel';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { HomeViewModel } from '../viewmodel/HomeViewModel';
import { RoomViewModel } from '../viewmodel/RoomViewModel';
import { SceneViewModel } from '../viewmodel/SceneViewModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import {
  AppContext
} from './AppContext';
import type {
  ActiveFamilyPort,
  AppContextRootPort,
  OnboardingPort,
  SessionGateAuthPort
} from './AppContext';
import {
  ActiveFamilyAdapter,
  ManualDiscoveryAdapter,
  RoomActorLookupAdapter,
  RoomSessionAdapter,
  SceneExecutionAuthAdapter,
  SessionGateAuthAdapter
} from './AppContextAdapters';
import { ActiveCloudScope } from './ActiveCloudScope';
import {
  ASSEMBLY_CONSTRUCTION_ORDER,
  ASSEMBLY_INITIALIZATION_ORDER,
  AssemblyTrace,
  ConstructionStep,
  InitializationStep
} from './CompositionPlan';
import { OnboardingService } from './OnboardingService';
import { BleViewModelPermissionGate, PermissionGate } from './PermissionGate';
import {
  HilogLogger,
  HilogMetrics,
  SystemClock,
  SystemSceneTimer,
  SystemVmTimer,
  UuidGenerator
} from './AppPlatformPorts';
import { ViewModelAppContextBridge } from './ViewModelAppContextBridge';
import type { PageVmFactoryPort } from './PageVmFactory';

const UI_CONNECT_TIMEOUT_MS: number = 2000;
const UI_READ_TIMEOUT_MS: number = 3000;
const UI_MAX_ATTEMPTS: number = 1;
const UI_DISCOVER_TIMEOUT_MS: number = 3000;
const RETRY_BASE_DELAY_MS: number = 300;
const RETRY_MAX_DELAY_MS: number = 900;
const DOMAIN_GATE_WAIT_MS: number = 2000;

export class AppCompositionRoot implements AppContextRootPort, PageVmFactoryPort {
  private readonly constructionTrace: AssemblyTrace =
    new AssemblyTrace(ASSEMBLY_CONSTRUCTION_ORDER);
  private readonly initializationTrace: AssemblyTrace =
    new AssemblyTrace(ASSEMBLY_INITIALIZATION_ORDER);

  private readonly context: common.UIAbilityContext;

  // 1. Platform
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly loggerPort: LoggerPort;
  private readonly metrics: MetricsPort;
  private readonly crypto: CryptoService;
  private readonly random: RandomPort;

  // 2. Storage adapters + 3. migrations + 4. StorageService
  private readonly preferencesAdapter: PreferencesStoreAdapter;
  private readonly rdbAdapter: RdbStoreAdapter;
  private readonly secretStore: AssetStoreSecretStore;
  private readonly drafts: SecretDraftStore;
  private readonly migrationRegistry: MigrationRegistry;
  private readonly storage: StorageService;

  // 6. Security
  private readonly signer: RequestSigner;
  private readonly verifier: ResponseVerifier;
  private readonly clockSkew: ClockSkewTracker;

  // 8-12. Repositories
  private readonly gatewayRepository: GatewayRepository;
  private readonly familyRepositoryValue: FamilyRepository;
  private readonly roomRepository: RoomRepository;
  private readonly sceneRepository: SceneRepository;
  private readonly deviceRepository: DeviceRepository;
  private readonly operationGate: DomainOperationGate;

  // 7/13/19. Services
  private readonly authService: AuthService;
  private readonly sessionAuthAdapter: SessionGateAuthAdapter;
  private readonly activeFamilyAdapter: ActiveFamilyAdapter;
  private readonly inviteService: InviteService;
  private readonly familyService: FamilyService;
  private readonly onboardingService: OnboardingService;
  private readonly roomService: RoomService;
  private readonly sceneService: SceneService;

  // 14-18. Transport/discovery/BLE
  private readonly httpTransport: OhosHttpTransport;
  private readonly uiClient: LocalGatewayService;
  private readonly backgroundClient: LocalGatewayService;
  private readonly discoveryService: GatewayDiscoveryService;
  private readonly bleService: BleProvisioningService;
  private readonly manualDiscoveryAdapter: ManualDiscoveryAdapter;

  // 19. Cloud
  private readonly activeCloudScope: ActiveCloudScope;
  private readonly cloudConfigStore: RdbCloudConfigStore;
  private readonly cloudCredentials: AssetCloudCredentialStore;
  private readonly cloudCommandClient: CloudCommandClient;
  private readonly shadowReader: ShadowReader;
  private readonly completionEvaluator: CloudCompletionEvaluator;
  private readonly cloudService: CloudService;

  // 20-21. Control
  private readonly commandRunner: DeviceCommandRunner;
  private readonly controlCoordinator: DeviceControlCoordinator;

  // 22. i18n
  private readonly i18nService: I18nService;

  // 23. AppContext + per-page seams
  private readonly appContextValue: AppContext;
  private readonly viewModelContext: ViewModelAppContextBridge;
  private readonly vmPermissionGate: BleViewModelPermissionGate;
  private readonly vmTimer: VmTimerPort;
  private readonly sceneTimer: SceneTimerPort;
  private readonly sceneAuthAdapter: SceneExecutionAuthAdapter;
  private readonly roomSessionAdapter: RoomSessionAdapter;
  private readonly roomActorAdapter: RoomActorLookupAdapter;

  private initPromise: Promise<void> | undefined = undefined;
  private initialized: boolean = false;
  private initializationErrorValue: AppError | undefined = undefined;
  private disposed: boolean = false;

  private constructor(context: common.UIAbilityContext) {
    this.context = context;

    // 1. Platform
    this.constructionTrace.record(ConstructionStep.PLATFORM);
    this.clock = new SystemClock();
    this.ids = new UuidGenerator();
    this.loggerPort = new HilogLogger();
    this.metrics = new HilogMetrics();
    // F-09 / DES-B §2.4: CryptoService is listed with the security stack
    // (step 5), but it only depends on OhosCryptoProvider/CryptoRandomSource
    // and has no storage edge, so it is constructed here. SECURITY still marks
    // the §2.4 security stack; CompositionPlan documents this deviation.
    this.crypto = new CryptoService(new OhosCryptoProvider());
    this.random = new CryptoRandomSource(this.crypto);

    // 2. Storage adapters
    this.constructionTrace.record(ConstructionStep.STORAGE_ADAPTERS);
    this.preferencesAdapter = new PreferencesStoreAdapter(context);
    this.rdbAdapter = new RdbStoreAdapter(context);
    this.secretStore = new AssetStoreSecretStore();
    this.drafts = new SecretDraftStore(this.random, this.clock);

    // 3. Migrations v2/v3/v4. v1 is registered by StorageService's constructor
    // (step 4); MigrationRegistry verifies contiguity at migrate() time.
    this.constructionTrace.record(ConstructionStep.MIGRATIONS);
    this.migrationRegistry = new MigrationRegistry();
    FamilyRepository.registerMigrations(this.migrationRegistry);
    AuthService.registerMigrations(this.migrationRegistry);
    DomainMigrations.register(this.migrationRegistry);

    // 4. StorageService
    this.constructionTrace.record(ConstructionStep.STORAGE_SERVICE);
    this.storage = new StorageService(this.preferencesAdapter, this.rdbAdapter,
      this.secretStore, this.migrationRegistry);

    // 6. Security
    this.constructionTrace.record(ConstructionStep.SECURITY);
    this.signer = new RequestSigner(this.crypto, this.clock, this.random,
      new NonceCache(this.clock));
    this.verifier = new ResponseVerifier(this.crypto);
    this.clockSkew = new ClockSkewTracker();

    // 8-12. Repositories. All C-08..C-11 repositories share one operation gate
    // (DES-B §2.8 O-1; D-023 bounded wait).
    this.constructionTrace.record(ConstructionStep.REPOSITORIES);
    this.operationGate = new DomainOperationGate(DOMAIN_GATE_WAIT_MS);
    this.gatewayRepository = new GatewayRepository(this.rdbAdapter,
      this.preferencesAdapter, this.secretStore, this.drafts, this.clock, this.ids);
    this.familyRepositoryValue = new FamilyRepository(this.rdbAdapter,
      this.preferencesAdapter, this.clock, this.ids, this.operationGate);
    this.roomRepository = new RoomRepository(this.rdbAdapter, this.clock, this.ids,
      this.operationGate);
    this.sceneRepository = new SceneRepository(this.rdbAdapter, this.clock, this.ids,
      this.operationGate);
    this.deviceRepository = new DeviceRepository(this.rdbAdapter, this.roomRepository,
      this.sceneRepository, this.clock, this.loggerPort, this.operationGate,
      this.gatewayRepository);

    // 7/13. Auth + invite + domain services that do not need the gateway client.
    this.constructionTrace.record(ConstructionStep.AUTH_SERVICE);
    this.authService = new AuthService(this.crypto, this.storage,
      this.familyRepositoryValue, this.clock, this.random, this.ids,
      AuthPolicy.defaults());
    this.sessionAuthAdapter = new SessionGateAuthAdapter(this.authService);
    this.activeFamilyAdapter = new ActiveFamilyAdapter(this.familyRepositoryValue);
    // F-02/F-03 (CQG-T18): UI capability and service refusal share the same
    // C-12 policy/member source.
    this.sceneAuthAdapter = new SceneExecutionAuthAdapter(this.authService);
    this.roomSessionAdapter = new RoomSessionAdapter(this.authService);
    this.roomActorAdapter = new RoomActorLookupAdapter(this.familyRepositoryValue);

    this.constructionTrace.record(ConstructionStep.INVITE_SERVICE);
    this.inviteService = new InviteService(this.crypto, this.secretStore,
      this.familyRepositoryValue, this.gatewayRepository, this.gatewayRepository,
      this.gatewayRepository, this.clock, this.random, this.ids);
    const inviteAdapter = new InviteServiceAdapter(this.inviteService);

    this.constructionTrace.record(ConstructionStep.DOMAIN_SERVICES);
    this.familyService = new FamilyService(this.familyRepositoryValue, inviteAdapter,
      this.authService, this.gatewayRepository, this.clock, this.ids, this.loggerPort,
      this.rdbAdapter, this.roomRepository, this.operationGate);
    this.onboardingService = new OnboardingService(this.familyService, this.authService);
    this.roomService = new RoomService(this.roomRepository, this.deviceRepository,
      this.familyRepositoryValue, this.rdbAdapter, this.clock, this.loggerPort,
      this.operationGate, this.deviceRepository, this.roomActorAdapter);

    // 14-16. Transport and the two client profiles.
    this.constructionTrace.record(ConstructionStep.GATEWAY_TRANSPORT);
    this.httpTransport = new OhosHttpTransport(this.crypto, this.clock);

    this.constructionTrace.record(ConstructionStep.GATEWAY_CLIENTS);
    const uiPolicy = new GatewayRequestPolicy(UI_CONNECT_TIMEOUT_MS, UI_READ_TIMEOUT_MS,
      UI_MAX_ATTEMPTS, RETRY_BASE_DELAY_MS, RETRY_MAX_DELAY_MS, UI_DISCOVER_TIMEOUT_MS,
      true);
    const backgroundPolicy = GatewayRequestPolicy.defaults();
    this.uiClient = new LocalGatewayService(this.httpTransport, this.signer,
      this.verifier, this.gatewayRepository, this.gatewayRepository,
      this.gatewayRepository, this.gatewayRepository, this.clock, this.clockSkew,
      this.loggerPort, this.metrics, uiPolicy);
    this.backgroundClient = new LocalGatewayService(this.httpTransport, this.signer,
      this.verifier, this.gatewayRepository, this.gatewayRepository,
      this.gatewayRepository, this.gatewayRepository, this.clock, this.clockSkew,
      this.loggerPort, this.metrics, backgroundPolicy);

    // Scene execution uses BACKGROUND (DES-B §2.4 note).
    this.constructionTrace.record(ConstructionStep.SCENE_SERVICE);
    this.sceneTimer = new SystemSceneTimer();
    this.sceneService = new SceneService(this.sceneRepository, this.deviceRepository,
      this.backgroundClient, this.gatewayRepository, this.clock, this.sceneTimer,
      this.ids, this.loggerPort, this.metrics, this.rdbAdapter, this.operationGate,
      this.sceneAuthAdapter);

    // 17. Discovery. PB-01 leaves the mDNS service type/TXT schema unresolved;
    // production passes no mDNS/UDP transport rather than guessing (DES-A §15.4).
    this.constructionTrace.record(ConstructionStep.DISCOVERY);
    this.discoveryService = new GatewayDiscoveryService(this.uiClient,
      this.gatewayRepository, undefined, undefined, this.gatewayRepository,
      this.clock, this.loggerPort);
    this.manualDiscoveryAdapter = new ManualDiscoveryAdapter(this.discoveryService);

    // 18. BLE provisioning
    this.constructionTrace.record(ConstructionStep.BLE);
    const bleTransport = new OhosBleTransport(new OhosBlePermissionGate(context));
    this.bleService = new BleProvisioningService(bleTransport, this.crypto, this.clock,
      this.random, this.backgroundClient, this.gatewayRepository, this.drafts,
      this.loggerPort);

    // 19. Cloud. ClockPort and CloudActiveScopePort are mandatory injections
    // (CQG-T14 F-06/R2-02); without scope the client fails closed.
    this.constructionTrace.record(ConstructionStep.CLOUD);
    this.activeCloudScope = new ActiveCloudScope(this.gatewayRepository);
    this.cloudConfigStore = new RdbCloudConfigStore(this.rdbAdapter, this.clock);
    this.cloudCredentials = new AssetCloudCredentialStore(this.secretStore, this.clock,
      this.preferencesAdapter);
    const cloudTransport = new OhosCloudHttpTransport(this.clock);
    this.cloudCommandClient = new CloudCommandClient(cloudTransport,
      this.cloudConfigStore, this.cloudCredentials, this.gatewayRepository,
      this.gatewayRepository, this.crypto, this.clock, this.random, this.loggerPort,
      CloudSendRetryPolicy.defaults(), this.activeCloudScope);
    this.shadowReader = new ShadowReader(cloudTransport, this.cloudConfigStore,
      this.cloudCredentials, this.crypto, this.clock, this.loggerPort);
    this.completionEvaluator = new CloudCompletionEvaluator(this.clock);
    this.cloudService = new CloudService(this.cloudConfigStore, this.cloudCredentials,
      this.cloudCommandClient, this.shadowReader, this.completionEvaluator, this.clock,
      new SystemTimerPort(), this.loggerPort, this.metrics);

    // 20-21. Control (LAN first, narrow cloud fallback)
    this.constructionTrace.record(ConstructionStep.DEVICE_COMMAND_RUNNER);
    this.commandRunner = new DeviceCommandRunner(this.uiClient, this.deviceRepository,
      this.clock, this.loggerPort, this.metrics);
    this.constructionTrace.record(ConstructionStep.CONTROL_COORDINATOR);
    this.controlCoordinator = new DeviceControlCoordinator(this.commandRunner,
      this.cloudService, this.deviceRepository, this.clock, this.loggerPort);

    // 22. i18n
    this.constructionTrace.record(ConstructionStep.I18N_SERVICE);
    this.i18nService = new I18nService(
      new RawfileI18nLoader(context.resourceManager),
      new OhosLocaleApplier(context.getApplicationContext()),
      this.preferencesAdapter, this.loggerPort);

    // 23. AppContext + page seams
    this.constructionTrace.record(ConstructionStep.APP_CONTEXT);
    this.appContextValue = new AppContext(this);
    this.activeCloudScope.setActiveFamilyIdProvider(
      (): string | undefined => this.appContextValue.activeFamilyId);
    this.viewModelContext = new ViewModelAppContextBridge(this.appContextValue,
      this.loggerPort);
    this.vmPermissionGate = new BleViewModelPermissionGate(
      new PermissionGate(context, this.loggerPort));
    this.vmTimer = new SystemVmTimer();
  }

  static create(context: common.UIAbilityContext): AppCompositionRoot {
    return new AppCompositionRoot(context);
  }

  initialize(): Promise<void> {
    if (this.initPromise !== undefined) {
      return this.initPromise;
    }
    this.initPromise = this.runInitialization();
    return this.initPromise;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  getInitializationError(): AppError | undefined {
    return this.initializationErrorValue;
  }

  // ---- Public services -----------------------------------------------------

  get i18n(): I18nService {
    return this.i18nService;
  }

  get auth(): AuthService {
    return this.authService;
  }

  get families(): FamilyService {
    return this.familyService;
  }

  get rooms(): RoomService {
    return this.roomService;
  }

  get devices(): DeviceRepository {
    return this.deviceRepository;
  }

  get scenes(): SceneService {
    return this.sceneService;
  }

  get cloud(): CloudService {
    return this.cloudService;
  }

  get gateways(): GatewayRepository {
    return this.gatewayRepository;
  }

  get discovery(): GatewayDiscoveryService {
    return this.discoveryService;
  }

  get ble(): IBleProvisioningClient {
    return this.bleService;
  }

  get uiGatewayClient(): IGatewayClient {
    return this.uiClient;
  }

  get backgroundGatewayClient(): IGatewayClient {
    return this.backgroundClient;
  }

  get appContext(): AppContext {
    return this.appContextValue;
  }

  /** C-28 UI seam: Index reads this once and passes it as an explicit prop. */
  get pageVms(): PageVmFactoryPort {
    return this;
  }

  // AppContextRootPort narrow getters
  get sessionAuth(): SessionGateAuthPort {
    return this.sessionAuthAdapter;
  }

  get activeFamily(): ActiveFamilyPort {
    return this.activeFamilyAdapter;
  }

  get onboarding(): OnboardingPort {
    return this.onboardingService;
  }

  get familyRepository(): FamilyRepository {
    return this.familyRepositoryValue;
  }

  get preferences(): PreferencesStore {
    return this.preferencesAdapter;
  }

  get secretDrafts(): SecretDraftPort {
    return this.drafts;
  }

  get logger(): LoggerPort {
    return this.loggerPort;
  }

  // ---- VM factories (per page, not global singletons) ----------------------

  createHomeViewModel(): HomeViewModel {
    return new HomeViewModel(this.familyService, this.roomService, this.deviceRepository,
      this.gatewayRepository, this.uiClient, this.manualDiscoveryAdapter, this.cloudService,
      this.viewModelContext, this.i18nService, this.clock, this.vmTimer, this.loggerPort);
  }

  createDeviceViewModel(): DeviceViewModel {
    return new DeviceViewModel(this.deviceRepository, this.roomService,
      this.controlCoordinator, this.i18nService, this.clock, this.vmTimer,
      this.loggerPort);
  }

  createClimateViewModel(): ClimateViewModel {
    return new ClimateViewModel(this.deviceRepository, this.controlCoordinator,
      this.i18nService, this.clock, this.vmTimer, this.loggerPort);
  }

  createDoorViewModel(): DoorViewModel {
    return new DoorViewModel(this.deviceRepository, this.controlCoordinator,
      this.i18nService, this.clock, this.vmTimer, this.loggerPort);
  }

  createFamilyViewModel(): FamilyViewModel {
    return new FamilyViewModel(this.familyService, this.authService,
      this.viewModelContext, this.i18nService, this.clock, this.loggerPort);
  }

  createRoomViewModel(): RoomViewModel {
    return new RoomViewModel(this.roomService, this.deviceRepository, this.i18nService,
      this.clock, this.loggerPort, this.roomSessionAdapter);
  }

  createSceneViewModel(): SceneViewModel {
    return new SceneViewModel(this.sceneService, this.deviceRepository, this.i18nService,
      this.loggerPort, this.sceneAuthAdapter);
  }

  createBleProvisioningViewModel(): BleProvisioningViewModel {
    return new BleProvisioningViewModel(this.bleService, this.gatewayRepository,
      this.familyRepositoryValue, this.drafts, this.crypto, this.vmPermissionGate,
      this.i18nService, this.clock, this.vmTimer, this.loggerPort);
  }

  createSettingsViewModel(): SettingsViewModel {
    return new SettingsViewModel(this.i18nService, this.cloudService,
      this.gatewayRepository, this.manualDiscoveryAdapter, this.authService,
      this.preferencesAdapter, this.clock, this.loggerPort, this.appVersion());
  }

  // ---- Lifecycle -----------------------------------------------------------

  async dispose(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    try {
      this.cloudService.stopPolling();
    } catch (error) {
      // Best-effort shutdown.
    }
    try {
      await this.bleService.cancel();
    } catch (error) {
      // Best-effort shutdown.
    }
    // F-08 / DES-B §17.1.2: dispose() clears the session/gate, not just
    // storage handles. AppContext.lock() locks AuthService and recomputes the
    // gate. Best-effort: a failure must not skip the closes below.
    try {
      await this.appContextValue.lock();
    } catch (error) {
      this.loggerPort.warn('AppCompositionRoot', 'dispose_lock_failed');
    }
    this.drafts.clearAll();
    this.i18nService.dispose();
    try {
      await this.storage.close();
      await this.rdbAdapter.close();
      await this.preferencesAdapter.close();
    } catch (error) {
      this.loggerPort.warn('AppCompositionRoot', 'dispose_storage_failed');
    }
    this.initialized = false;
  }

  private async runInitialization(): Promise<void> {
    try {
      this.initializationTrace.record(InitializationStep.STORAGE);
      await this.storage.initialize();

      this.initializationTrace.record(InitializationStep.AUTH);
      await this.authService.initialize();

      this.initializationTrace.record(InitializationStep.GATEWAY);
      await this.gatewayRepository.initialize();

      this.initializationTrace.record(InitializationStep.FAMILY);
      await this.familyRepositoryValue.initialize();

      this.initializationTrace.record(InitializationStep.ROOM);
      await this.roomRepository.initialize();

      this.initializationTrace.record(InitializationStep.SCENE);
      await this.sceneRepository.initialize();

      this.initializationTrace.record(InitializationStep.DEVICE);
      await this.deviceRepository.initialize();

      this.initializationTrace.record(InitializationStep.CLOUD);
      await this.cloudConfigStore.initialize();
      await this.cloudService.initialize();

      this.initializationTrace.record(InitializationStep.I18N);
      await this.i18nService.initialize();

      this.initializationErrorValue = undefined;
      this.initialized = true;
    } catch (error) {
      this.initializationErrorValue = AppCompositionRoot.asAppError(error as Error);
      this.initialized = false;
      this.initPromise = undefined;
      throw this.initializationErrorValue;
    }
  }

  private appVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(0).versionName;
    } catch (error) {
      return '';
    }
  }

  private static asAppError(error: Error): AppError {
    if (error instanceof AppError) {
      return error as AppError;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }
}
