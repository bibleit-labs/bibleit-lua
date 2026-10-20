# API parity inventory

Public API parity target: [bibleit-go](https://github.com/bibleit-labs/bibleit-go).

The entries below have Lua implementations. REST bindings are checked against the
contract; schemas retain their wire metadata; helper families have fixture tests.
Lua names use snake_case and wire operation IDs remain unchanged. See [API usage](api.md).

## REST operations (88)

| Operation ID | HTTP | Path | Status |
| --- | --- | --- | --- |
| `clearLiveStack` | DELETE | `/lives/{live_id}/stack` | Implemented |
| `createLive` | POST | `/organizations/{organization_id}/lives` | Implemented |
| `createLiveAudienceSecret` | POST | `/lives/{live_id}/audience-secret` | Implemented |
| `createLiveQueueItem` | POST | `/lives/{live_id}/queue-items` | Implemented |
| `createPersonalLive` | POST | `/accounts/{account_id}/lives` | Implemented |
| `createPresentation` | POST | `/organizations/{organization_id}/presentations` | Implemented |
| `createPresentationExport` | POST | `/presentations/{presentation_id}/exports` | Implemented |
| `createServiceToken` | POST | `/organizations/{organization_id}/service-tokens` | Implemented |
| `deleteLive` | DELETE | `/lives/{live_id}` | Implemented |
| `deleteLiveAudienceSecret` | DELETE | `/lives/{live_id}/audience-secret` | Implemented |
| `deleteLiveQueueItem` | DELETE | `/lives/{live_id}/queue-items/{item_id}` | Implemented |
| `deleteOrganizationLives` | DELETE | `/organizations/{organization_id}/lives` | Implemented |
| `deleteOrganizationMember` | DELETE | `/organizations/{organization_id}/members/{member_id}` | Implemented |
| `deletePersonalLives` | DELETE | `/accounts/{account_id}/lives` | Implemented |
| `deletePresentation` | DELETE | `/presentations/{presentation_id}` | Implemented |
| `disableOrganizationTranslation` | DELETE | `/organizations/{organization_id}/translations/{slug}` | Implemented |
| `disablePersonalTranslation` | DELETE | `/accounts/{account_id}/translations/{slug}` | Implemented |
| `downloadPresentationExport` | POST | `/presentations/{presentation_id}/exports/{export_id}/downloads` | Implemented |
| `enableOrganizationTranslation` | PUT | `/organizations/{organization_id}/translations/{slug}` | Implemented |
| `enablePersonalTranslation` | PUT | `/accounts/{account_id}/translations/{slug}` | Implemented |
| `getLive` | GET | `/lives/{live_id}` | Implemented |
| `getLiveDisplay` | GET | `/lives/{live_id}/display` | Implemented |
| `getLiveEvents` | GET | `/lives/{live_id}/events` | Implemented |
| `getLivePlayback` | GET | `/lives/{live_id}/playback` | Implemented |
| `getLiveQueueItem` | GET | `/lives/{live_id}/queue-items/{item_id}` | Implemented |
| `getLiveSettings` | GET | `/lives/{live_id}/settings` | Implemented |
| `getLiveStack` | GET | `/lives/{live_id}/stack` | Implemented |
| `getLiveStatistics` | GET | `/lives/{live_id}/statistics` | Implemented |
| `getOpenApi` | GET | `/openapi.json` | Implemented |
| `getOrganization` | GET | `/organizations/{organization_id}` | Implemented |
| `getOrganizationLiveStudio` | GET | `/organizations/{organization_id}/live-studio` | Implemented |
| `getOrganizationMember` | GET | `/organizations/{organization_id}/members/{member_id}` | Implemented |
| `getOrganizationQuotas` | GET | `/organizations/{organization_id}/quotas` | Implemented |
| `getOrganizationTranslation` | GET | `/organizations/{organization_id}/translations/{slug}` | Implemented |
| `getPersonalAccount` | GET | `/accounts/{account_id}` | Implemented |
| `getPersonalIdentity` | GET | `/me` | Implemented |
| `getPersonalOrganizationApplication` | GET | `/me/organization-applications/{application_id}` | Implemented |
| `getPersonalQuotas` | GET | `/accounts/{account_id}/quotas` | Implemented |
| `getPersonalTranslation` | GET | `/accounts/{account_id}/translations/{slug}` | Implemented |
| `getPresentation` | GET | `/presentations/{presentation_id}` | Implemented |
| `getPresentationAsset` | GET | `/presentations/{presentation_id}/assets/{asset_id}` | Implemented |
| `getPresentationExport` | GET | `/presentations/{presentation_id}/exports/{export_id}` | Implemented |
| `getServiceOrganization` | GET | `/organization` | Implemented |
| `getServiceToken` | GET | `/organizations/{organization_id}/service-tokens/{credential_id}` | Implemented |
| `getTranslation` | GET | `/translations/{slug}` | Implemented |
| `getTranslationCatalogueDetails` | GET | `/translations/{slug}/catalogue` | Implemented |
| `importPresentation` | POST | `/organizations/{organization_id}/presentation-imports` | Implemented |
| `listBooks` | GET | `/books` | Implemented |
| `listLiveQueueItems` | GET | `/lives/{live_id}/queue-items` | Implemented |
| `listLives` | GET | `/organizations/{organization_id}/lives` | Implemented |
| `listOAuthGrants` | GET | `/me/oauth-grants` | Implemented |
| `listOrganizationMembers` | GET | `/organizations/{organization_id}/members` | Implemented |
| `listOrganizationTranslations` | GET | `/organizations/{organization_id}/translations` | Implemented |
| `listPersonalAccounts` | GET | `/accounts` | Implemented |
| `listPersonalLives` | GET | `/accounts/{account_id}/lives` | Implemented |
| `listPersonalOrganizations` | GET | `/me/organizations` | Implemented |
| `listPersonalTokens` | GET | `/accounts/{account_id}/tokens` | Implemented |
| `listPersonalTranslations` | GET | `/accounts/{account_id}/translations` | Implemented |
| `listPresentationExports` | GET | `/presentations/{presentation_id}/exports` | Implemented |
| `listPresentations` | GET | `/organizations/{organization_id}/presentations` | Implemented |
| `listServiceTokens` | GET | `/organizations/{organization_id}/service-tokens` | Implemented |
| `listTranslationBooks` | GET | `/translations/{slug}/books` | Implemented |
| `listTranslationCatalogue` | GET | `/translations` | Implemented |
| `moveLiveWorkspace` | PUT | `/lives/{live_id}/workspace` | Implemented |
| `popLiveStack` | POST | `/lives/{live_id}/stack/removals` | Implemented |
| `pushLiveStack` | POST | `/lives/{live_id}/stack` | Implemented |
| `readBook` | GET | `/organizations/{organization_id}/translations/{slug}/books/{book_id}` | Implemented |
| `readChapter` | GET | `/organizations/{organization_id}/translations/{slug}/books/{book_id}/chapters/{chapter}` | Implemented |
| `readPersonalBook` | GET | `/accounts/{account_id}/translations/{slug}/books/{book_id}` | Implemented |
| `readPersonalChapter` | GET | `/accounts/{account_id}/translations/{slug}/books/{book_id}/chapters/{chapter}` | Implemented |
| `readPersonalVerse` | GET | `/accounts/{account_id}/translations/{slug}/books/{book_id}/chapters/{chapter}/verses/{verse}` | Implemented |
| `readVerse` | GET | `/organizations/{organization_id}/translations/{slug}/books/{book_id}/chapters/{chapter}/verses/{verse}` | Implemented |
| `replaceLiveDisplay` | PUT | `/lives/{live_id}/display` | Implemented |
| `replaceLiveQueueOrder` | PUT | `/lives/{live_id}/queue-items/order` | Implemented |
| `replaceOrganizationLiveStudio` | PUT | `/organizations/{organization_id}/live-studio` | Implemented |
| `replacePresentation` | PUT | `/presentations/{presentation_id}` | Implemented |
| `revokeOAuthGrant` | DELETE | `/me/oauth-grants/{grant_id}` | Implemented |
| `revokeServiceToken` | DELETE | `/organizations/{organization_id}/service-tokens/{credential_id}` | Implemented |
| `rotateLiveAudienceSecret` | PUT | `/lives/{live_id}/audience-secret` | Implemented |
| `rotateServiceToken` | POST | `/organizations/{organization_id}/service-tokens/{credential_id}/rotations` | Implemented |
| `searchPersonalScripture` | GET | `/accounts/{account_id}/translations/{slug}/search` | Implemented |
| `searchScripture` | GET | `/organizations/{organization_id}/translations/{slug}/search` | Implemented |
| `updateLiveMetadata` | PATCH | `/lives/{live_id}` | Implemented |
| `updateLivePlayback` | PATCH | `/lives/{live_id}/playback` | Implemented |
| `updateLiveSettings` | PATCH | `/lives/{live_id}/settings` | Implemented |
| `updateOrganizationMember` | PATCH | `/organizations/{organization_id}/members/{member_id}` | Implemented |
| `updateServiceToken` | PATCH | `/organizations/{organization_id}/service-tokens/{credential_id}` | Implemented |
| `uploadPresentationAsset` | POST | `/presentations/{presentation_id}/assets` | Implemented |

## Public Go functions and methods

Includes constructors, command builders, transport helpers and error helpers.
Generated operation wrappers are covered above; generated model helpers map to
the schema representations below. Go-specific methods need documented Lua equivalents.

| Go API | Lua equivalent |
| --- | --- |
| `NewAuthClient` | `bibleit.new_auth_client` |
| `NewAuthClientWithHTTPClient` | `bibleit.new_auth_client_with_http_client` |
| `AuthClient.ExchangeCode` | `exchange_code` |
| `Client.RevokeCredential` | `revoke_credential` |
| `RequestSizeError.Error` | `tostring(err)` |
| `NewClient` | `bibleit.new_client` |
| `NewClientWithHTTPClient` | `bibleit.new_client_with_http_client` |
| `HTTPError.Error` | `tostring(err)` |
| `NewSSHClient` | `bibleit.new_ssh_client` |
| `SSHClient.Execute` | `execute` |
| `SSHClient.Read` | `read` |
| `SSHClient.Search` | `search` |
| `SSHClient.Ping` | `ping` |
| `SSHClient.Identity` | `identity` |
| `SSHClient.ListTranslations` | `list_translations` |
| `Command.String` | `command:string()` |
| `Command.Streaming` | `command:streaming()` |
| `PingCommand` | `ping_command` |
| `ServerInfoCommand` | `server_info_command` |
| `IdentityCommand` | `identity_command` |
| `AccountTokensCommand` | `account_tokens_command` |
| `TranslationListCommand` | `translation_list_command` |
| `AddTranslationCommand` | `add_translation_command` |
| `RemoveTranslationCommand` | `remove_translation_command` |
| `ReadCommand` | `read_command` |
| `SearchCommand` | `search_command` |
| `LiveListCommand` | `live_list_command` |
| `CreateLiveCommand` | `create_live_command` |
| `DeleteAllLivesCommand` | `delete_all_lives_command` |
| `LiveCommand` | `live_command` |
| `SetLiveCommand` | `set_live_command` |
| `LiveSecretCommand` | `live_secret_command` |
| `LiveStackCommand` | `live_stack_command` |
| `PushLiveCommand` | `push_live_command` |
| `PopLiveCommand` | `pop_live_command` |
| `HelpCommand` | `help_command` |
| `AccountInfoCommand` | `account_info_command` |
| `AccountQuotasCommand` | `account_quotas_command` |
| `TranslationInfoCommand` | `translation_info_command` |
| `TranslationCatalogCommand` | `translation_catalog_command` |
| `SSHClient.GetServerInfo` | `get_server_info` |
| `SSHClient.Help` | `help` |
| `SSHClient.GetAccountInfo` | `get_account_info` |
| `SSHClient.ListQuotas` | `list_quotas` |
| `SSHClient.GetIdentity` | `get_identity` |
| `SSHClient.ReadVerses` | `read_verses` |
| `SSHClient.SearchVerses` | `search_verses` |
| `SSHClient.CreateLive` | `create_live` |
| `SSHClient.GetLive` | `get_live` |
| `SSHClient.SetLive` | `set_live` |
| `SSHClient.ListLives` | `list_lives` |
| `SSHClient.GetLiveStats` | `get_live_stats` |
| `SSHClient.GetLiveStack` | `get_live_stack` |
| `SSHClient.PushLive` | `push_live` |
| `SSHClient.PopLive` | `pop_live` |
| `SSHClient.ControlLive` | `control_live` |
| `OrganizationListCommand` | `organization_list_command` |
| `OrganizationApplicationStatusCommand` | `organization_application_status_command` |
| `SSHClient.ListOrganizations` | `list_organizations` |
| `SSHClient.GetOrganizationApplicationStatus` | `get_organization_application_status` |
| `ServerError.Error` | `tostring(err)` |
| `ServerError.RetryAfter` | `err:retry_after()` |
| `ParseRecord` | `parse_record` |
| `DecodeResponse` | `decode_response` |
| `DecodeCommandResponse` | `decode_command_response` |
| `SSHClient.ListTokens` | `list_tokens` |
| `SSHClient.GetTranslationInfo` | `get_translation_info` |
| `SSHClient.GetTranslationCatalog` | `get_translation_catalog` |
| `Operations` | `bibleit.operations` |
| `OperationNames` | `bibleit.operation_names` |
| `Response.Decode` | `response:decode()` |
| `ProblemError.Error` | `tostring(err)` |
| `ProblemError.RetryAfter` | `err:retry_after()` |
| `Client.Call` | `call` |
| `NewOAuthClient` | `bibleit.new_oauth_client` |
| `OAuthProtocolError.Error` | `tostring(err)` |
| `AuthorizationURL` | `bibleit.authorization_url` |
| `OAuthClient.Metadata` | `metadata` |
| `OAuthClient.ExchangeCode` | `exchange_code` |
| `OAuthClient.Refresh` | `refresh` |
| `OAuthClient.Revoke` | `revoke` |
| `Client.PollLiveEvents` | `poll_live_events` |
| `Client.ReadPersonalBookPages` | `read_personal_book_pages` |
| `Client.ReadBookPages` | `read_book_pages` |

## Schema representations (105)

Wire fields, nullability, enums and union semantics are represented through Lua
tables and schema metadata; generated Go conversion helpers map to the documented
Lua constructor/union helpers.

| Schema | Status |
| --- | --- |
| `AccountQuota` | Implemented |
| `AccountQuotaCollection` | Implemented |
| `BookCollection` | Implemented |
| `BookDefinition` | Implemented |
| `CatalogueTranslation` | Implemented |
| `CreateLive` | Implemented |
| `CreateLiveQueueItem` | Implemented |
| `CreatePresentation` | Implemented |
| `CreatePresentationExport` | Implemented |
| `CreateServiceToken` | Implemented |
| `DisplayVerse` | Implemented |
| `EmptyObject` | Implemented |
| `IssuedServiceToken` | Implemented |
| `Live` | Implemented |
| `LiveAudienceSecret` | Implemented |
| `LiveBulkDeletion` | Implemented |
| `LiveDisplay` | Implemented |
| `LiveEvent` | Implemented |
| `LiveEventDesign` | Implemented |
| `LiveEventSnapshot` | Implemented |
| `LiveEventViewerSettings` | Implemented |
| `LiveHeartbeatEvent` | Implemented |
| `LiveList` | Implemented |
| `LiveMetadataPatch` | Implemented |
| `LiveQueueItem` | Implemented |
| `LiveQueueOrder` | Implemented |
| `LiveQueuePage` | Implemented |
| `LiveSettings` | Implemented |
| `LiveSettingsPatch` | Implemented |
| `LiveSnapshotEvent` | Implemented |
| `LiveStack` | Implemented |
| `LiveStackPush` | Implemented |
| `LiveStackReference` | Implemented |
| `LiveStackRemoval` | Implemented |
| `LiveStackVerse` | Implemented |
| `LiveStatistics` | Implemented |
| `LiveStudioSettings` | Implemented |
| `LiveStudioSettingsInput` | Implemented |
| `LiveSubscriber` | Implemented |
| `LiveSummary` | Implemented |
| `LiveWorkspacePut` | Implemented |
| `Membership` | Implemented |
| `MembershipPage` | Implemented |
| `MembershipPatch` | Implemented |
| `OAuthError` | Implemented |
| `OAuthGrant` | Implemented |
| `OAuthGrantList` | Implemented |
| `OAuthMetadata` | Implemented |
| `OAuthScope` | Implemented |
| `OAuthToken` | Implemented |
| `Organization` | Implemented |
| `OrganizationLiveStudio` | Implemented |
| `PatchServiceToken` | Implemented |
| `PersonalAccount` | Implemented |
| `PersonalAccountList` | Implemented |
| `PersonalDirectory` | Implemented |
| `PersonalDirectoryEntry` | Implemented |
| `PersonalIdentity` | Implemented |
| `PersonalLive` | Implemented |
| `PersonalLiveDisplay` | Implemented |
| `PersonalLiveList` | Implemented |
| `PersonalLiveQueuePage` | Implemented |
| `PersonalLiveSummary` | Implemented |
| `PersonalOrganizationApplication` | Implemented |
| `PersonalTokenCollection` | Implemented |
| `PersonalTokenMetadata` | Implemented |
| `Playback` | Implemented |
| `PlaybackPatch` | Implemented |
| `Presentation` | Implemented |
| `PresentationAsset` | Implemented |
| `PresentationDisplayReference` | Implemented |
| `PresentationDocument` | Implemented |
| `PresentationElement` | Implemented |
| `PresentationElementStyle` | Implemented |
| `PresentationExport` | Implemented |
| `PresentationExportList` | Implemented |
| `PresentationImageElement` | Implemented |
| `PresentationPage` | Implemented |
| `PresentationShapeElement` | Implemented |
| `PresentationSlide` | Implemented |
| `PresentationSummary` | Implemented |
| `PresentationTextElement` | Implemented |
| `PresentationVerseElement` | Implemented |
| `PresentationVideoElement` | Implemented |
| `PresentationYouTubeElement` | Implemented |
| `Problem` | Implemented |
| `PutOrganizationLiveStudio` | Implemented |
| `PutPresentation` | Implemented |
| `ReplaceDisplay` | Implemented |
| `Scope` | Implemented |
| `ScriptureBookRead` | Implemented |
| `ScriptureRead` | Implemented |
| `ScriptureReference` | Implemented |
| `ScriptureSearch` | Implemented |
| `ServiceToken` | Implemented |
| `ServiceTokenConfiguration` | Implemented |
| `ServiceTokenList` | Implemented |
| `SnapshotSummary` | Implemented |
| `TranslationBookMetadata` | Implemented |
| `TranslationCatalogueDetails` | Implemented |
| `TranslationChapterMetadata` | Implemented |
| `TranslationCollection` | Implemented |
| `TranslationProvenance` | Implemented |
| `TranslationRights` | Implemented |
| `Verse` | Implemented |
