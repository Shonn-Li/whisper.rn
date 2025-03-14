whisper.rn

# whisper.rn

## Table of contents

### Enumerations

- [AudioSessionCategoryIos](enums/AudioSessionCategoryIos.md)
- [AudioSessionCategoryOptionIos](enums/AudioSessionCategoryOptionIos.md)
- [AudioSessionModeIos](enums/AudioSessionModeIos.md)

### Classes

- [WhisperContext](classes/WhisperContext.md)

### Type Aliases

- [AudioSessionSettingIos](README.md#audiosessionsettingios)
- [BenchResult](README.md#benchresult)
- [ContextOptions](README.md#contextoptions)
- [TranscribeFileOptions](README.md#transcribefileoptions)
- [TranscribeNewSegmentsNativeEvent](README.md#transcribenewsegmentsnativeevent)
- [TranscribeNewSegmentsResult](README.md#transcribenewsegmentsresult)
- [TranscribeOptions](README.md#transcribeoptions)
- [TranscribeProgressNativeEvent](README.md#transcribeprogressnativeevent)
- [TranscribeRealtimeEvent](README.md#transcriberealtimeevent)
- [TranscribeRealtimeNativeEvent](README.md#transcriberealtimenativeevent)
- [TranscribeRealtimeNativePayload](README.md#transcriberealtimenativepayload)
- [TranscribeRealtimeOptions](README.md#transcriberealtimeoptions)
- [TranscribeRealtimeVolumeNativePayload](README.md#transcriberealtimevolumenativepayload)
- [TranscribeResult](README.md#transcriberesult)

### Variables

- [AudioSessionIos](README.md#audiosessionios)
- [isCoreMLAllowFallback](README.md#iscoremlallowfallback)
- [isUseCoreML](README.md#isusecoreml)
- [libVersion](README.md#libversion)

### Functions

- [initWhisper](README.md#initwhisper)
- [releaseAllWhisper](README.md#releaseallwhisper)

## Type Aliases

### AudioSessionSettingIos

Ƭ **AudioSessionSettingIos**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `active?` | `boolean` |
| `category` | [`AudioSessionCategoryIos`](enums/AudioSessionCategoryIos.md) |
| `mode?` | [`AudioSessionModeIos`](enums/AudioSessionModeIos.md) |
| `options?` | [`AudioSessionCategoryOptionIos`](enums/AudioSessionCategoryOptionIos.md)[] |

#### Defined in

[index.ts:77](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L77)

___

### BenchResult

Ƭ **BenchResult**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `batchMs` | `number` |
| `config` | `string` |
| `decodeMs` | `number` |
| `encodeMs` | `number` |
| `nThreads` | `number` |
| `promptMs` | `number` |

#### Defined in

[index.ts:189](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L189)

___

### ContextOptions

Ƭ **ContextOptions**: `Object`

#### Type declaration

| Name | Type | Description |
| :------ | :------ | :------ |
| `coreMLModelAsset?` | \{ `assets`: `string`[] \| `number`[] ; `filename`: `string`  } | CoreML model assets, if you're using `require` on filePath, use this option is required if you want to enable Core ML, you will need bundle weights/weight.bin, model.mil, coremldata.bin into app by `require` |
| `coreMLModelAsset.assets` | `string`[] \| `number`[] | - |
| `coreMLModelAsset.filename` | `string` | - |
| `filePath` | `string` \| `number` | - |
| `isBundleAsset?` | `boolean` | Is the file path a bundle asset for pure string filePath |
| `useCoreMLIos?` | `boolean` | Prefer to use Core ML model if exists. If set to false, even if the Core ML model exists, it will not be used. |
| `useFlashAttn?` | `boolean` | Use Flash Attention, only recommended if GPU available |
| `useGpu?` | `boolean` | Use GPU if available. Currently iOS only, if it's enabled, Core ML option will be ignored. |

#### Defined in

[index.ts:520](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L520)

___

### TranscribeFileOptions

Ƭ **TranscribeFileOptions**: [`TranscribeOptions`](README.md#transcribeoptions) & \{ `onNewSegments?`: (`result`: [`TranscribeNewSegmentsResult`](README.md#transcribenewsegmentsresult)) => `void` ; `onProgress?`: (`progress`: `number`) => `void`  }

#### Defined in

[index.ts:60](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L60)

___

### TranscribeNewSegmentsNativeEvent

Ƭ **TranscribeNewSegmentsNativeEvent**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `contextId` | `number` |
| `jobId` | `number` |
| `result` | [`TranscribeNewSegmentsResult`](README.md#transcribenewsegmentsresult) |

#### Defined in

[index.ts:53](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L53)

___

### TranscribeNewSegmentsResult

Ƭ **TranscribeNewSegmentsResult**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `nNew` | `number` |
| `result` | `string` |
| `segments` | [`TranscribeResult`](README.md#transcriberesult)[``"segments"``] |
| `totalNNew` | `number` |

#### Defined in

[index.ts:46](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L46)

___

### TranscribeOptions

Ƭ **TranscribeOptions**: `Object`

#### Type declaration

| Name | Type | Description |
| :------ | :------ | :------ |
| `beamSize?` | `number` | Beam size for beam search |
| `bestOf?` | `number` | Number of best candidates to keep |
| `duration?` | `number` | Duration of audio to process in milliseconds |
| `language?` | `string` | Spoken language (Default: 'auto' for auto-detect) |
| `maxContext?` | `number` | Maximum number of text context tokens to store |
| `maxLen?` | `number` | Maximum segment length in characters |
| `maxThreads?` | `number` | Number of threads to use during computation (Default: 2 for 4-core devices, 4 for more cores) |
| `offset?` | `number` | Time offset in milliseconds |
| `prompt?` | `string` | Initial Prompt |
| `tdrzEnable?` | `boolean` | Enable tinydiarize (requires a tdrz model) |
| `temperature?` | `number` | Tnitial decoding temperature |
| `temperatureInc?` | `number` | - |
| `tokenTimestamps?` | `boolean` | Enable token-level timestamps |
| `translate?` | `boolean` | Translate from source language to english (Default: false) |
| `wordThold?` | `number` | Word timestamp probability threshold |

#### Defined in

[NativeRNWhisper.ts:5](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/NativeRNWhisper.ts#L5)

___

### TranscribeProgressNativeEvent

Ƭ **TranscribeProgressNativeEvent**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `contextId` | `number` |
| `jobId` | `number` |
| `progress` | `number` |

#### Defined in

[index.ts:71](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L71)

___

### TranscribeRealtimeEvent

Ƭ **TranscribeRealtimeEvent**: `Object`

#### Type declaration

| Name | Type | Description |
| :------ | :------ | :------ |
| `code` | `number` | - |
| `contextId` | `number` | - |
| `data?` | [`TranscribeResult`](README.md#transcriberesult) | - |
| `error?` | `string` | - |
| `isCapturing` | `boolean` | Is capturing audio, when false, the event is the final result |
| `isStoppedByAction?` | `boolean` | - |
| `jobId` | `number` | - |
| `processTime` | `number` | - |
| `recordingTime` | `number` | - |
| `slices?` | \{ `code`: `number` ; `data?`: [`TranscribeResult`](README.md#transcriberesult) ; `error?`: `string` ; `processTime`: `number` ; `recordingTime`: `number`  }[] | - |

#### Defined in

[index.ts:139](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L139)

___

### TranscribeRealtimeNativeEvent

Ƭ **TranscribeRealtimeNativeEvent**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `contextId` | `number` |
| `jobId` | `number` |
| `payload` | [`TranscribeRealtimeNativePayload`](README.md#transcriberealtimenativepayload) |

#### Defined in

[index.ts:172](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L172)

___

### TranscribeRealtimeNativePayload

Ƭ **TranscribeRealtimeNativePayload**: `Object`

#### Type declaration

| Name | Type | Description |
| :------ | :------ | :------ |
| `code` | `number` | - |
| `data?` | [`TranscribeResult`](README.md#transcriberesult) | - |
| `error?` | `string` | - |
| `isCapturing` | `boolean` | Is capturing audio, when false, the event is the final result |
| `isStoppedByAction?` | `boolean` | - |
| `isUseSlices` | `boolean` | - |
| `processTime` | `number` | - |
| `recordingTime` | `number` | - |
| `sliceIndex` | `number` | - |

#### Defined in

[index.ts:159](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L159)

___

### TranscribeRealtimeOptions

Ƭ **TranscribeRealtimeOptions**: [`TranscribeOptions`](README.md#transcribeoptions) & \{ `audioOutputPath?`: `string` ; `audioSessionOnStartIos?`: [`AudioSessionSettingIos`](README.md#audiosessionsettingios) ; `audioSessionOnStopIos?`: `string` \| [`AudioSessionSettingIos`](README.md#audiosessionsettingios) ; `realtimeAudioMinSec?`: `number` ; `realtimeAudioSec?`: `number` ; `realtimeAudioSliceSec?`: `number` ; `useVad?`: `boolean` ; `vadFreqThold?`: `number` ; `vadMs?`: `number` ; `vadThold?`: `number`  }

#### Defined in

[index.ts:85](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L85)

___

### TranscribeRealtimeVolumeNativePayload

Ƭ **TranscribeRealtimeVolumeNativePayload**: `Object`

#### Type declaration

| Name | Type | Description |
| :------ | :------ | :------ |
| `volume` | `number` | Is capturing audio, when false, the event is the final result |

#### Defined in

[index.ts:178](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L178)

___

### TranscribeResult

Ƭ **TranscribeResult**: `Object`

#### Type declaration

| Name | Type |
| :------ | :------ |
| `isAborted` | `boolean` |
| `result` | `string` |
| `segments` | \{ `t0`: `number` ; `t1`: `number` ; `text`: `string`  }[] |

#### Defined in

[NativeRNWhisper.ts:37](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/NativeRNWhisper.ts#L37)

## Variables

### AudioSessionIos

• **AudioSessionIos**: `Object`

AudioSession Utility, iOS only.

#### Type declaration

| Name | Type |
| :------ | :------ |
| `Category` | typeof [`AudioSessionCategoryIos`](enums/AudioSessionCategoryIos.md) |
| `CategoryOption` | typeof [`AudioSessionCategoryOptionIos`](enums/AudioSessionCategoryOptionIos.md) |
| `Mode` | typeof [`AudioSessionModeIos`](enums/AudioSessionModeIos.md) |
| `getCurrentCategory` | () => `Promise`\<\{ `category`: [`AudioSessionCategoryIos`](enums/AudioSessionCategoryIos.md) ; `options`: [`AudioSessionCategoryOptionIos`](enums/AudioSessionCategoryOptionIos.md)[]  }\> |
| `getCurrentMode` | () => `Promise`\<[`AudioSessionModeIos`](enums/AudioSessionModeIos.md)\> |
| `setActive` | (`active`: `boolean`) => `Promise`\<`void`\> |
| `setCategory` | (`category`: [`AudioSessionCategoryIos`](enums/AudioSessionCategoryIos.md), `options`: [`AudioSessionCategoryOptionIos`](enums/AudioSessionCategoryOptionIos.md)[]) => `Promise`\<`void`\> |
| `setMode` | (`mode`: [`AudioSessionModeIos`](enums/AudioSessionModeIos.md)) => `Promise`\<`void`\> |

#### Defined in

[AudioSessionIos.ts:50](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/AudioSessionIos.ts#L50)

___

### isCoreMLAllowFallback

• `Const` **isCoreMLAllowFallback**: `boolean` = `!!coreMLAllowFallback`

Is allow fallback to CPU if load CoreML model failed

#### Defined in

[index.ts:626](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L626)

___

### isUseCoreML

• `Const` **isUseCoreML**: `boolean` = `!!useCoreML`

Is use CoreML models on iOS

#### Defined in

[index.ts:623](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L623)

___

### libVersion

• `Const` **libVersion**: `string` = `version`

Current version of whisper.cpp

#### Defined in

[index.ts:618](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L618)

## Functions

### initWhisper

▸ **initWhisper**(`«destructured»`): `Promise`\<[`WhisperContext`](classes/WhisperContext.md)\>

#### Parameters

| Name | Type |
| :------ | :------ |
| `«destructured»` | [`ContextOptions`](README.md#contextoptions) |

#### Returns

`Promise`\<[`WhisperContext`](classes/WhisperContext.md)\>

#### Defined in

[index.ts:548](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L548)

___

### releaseAllWhisper

▸ **releaseAllWhisper**(): `Promise`\<`void`\>

#### Returns

`Promise`\<`void`\>

#### Defined in

[index.ts:613](https://github.com/Shonn-Li/whisper.rn/blob/78d762f/src/index.ts#L613)
