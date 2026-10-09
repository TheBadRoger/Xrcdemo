# 改动点总表 —— 静态焊改 + 数据改动（7.0.256 / build 1209864）

[返回 README](../README.md) · [版本适配指南](version-adaptation.md) · [实现原理](architecture.md)

本文把本轮改包**所有落盘改动**登记成表：**要改什么（目的）／改了哪里（函数·VA·fileoff）／怎么改（原字节 → 新字节、脚本）**，并给出换版本时的重定位锚点。换版本时按第 4 节的套路重新定位，逐个脚本改断言字节即可。

> 铁律：每个改动都是**等长原地覆写 + apply 前断言旧字节**；改完必须让 `host\deployment\package_patched_nocb.py` 的 `EXPECT_MAIN_SHA` 与新主程序一致（weld 脚本会自动同步），否则打包会直接拒。

---

## 0. 基本事实与构建链

| 项 | 值 |
| --- | --- |
| 主程序 | `host\deployment\target-bin\main\Arc-mobile`，24,899,920 B |
| 地址换算 | `fileoff = VA - 0x100000000`（__TEXT/__DATA 同规则；__PAGEZERO 无文件背衬） |
| 当前主程序 | sha256 `bcaf98839ced5945db1cffe26dca20a914c059ac2b9cb63a7311c436545b526f` |
| 当前未签名 IPA | `host\deployment\Arc-Exercise-7.0.256-unlocked-songs-unsigned.ipa`，3,278,254,325 B，sha256 `f88e953e56da8cd37cb31a72990002571f08f059a63c7f17fb75b45b4de4b608`，8,632 条目 |
| 内容包 | `host\deployment\Arc-Exercise-content-7.0.260-container-ready.zip`（由 `host\request\cb` 分片生成） |
| 改主程序 | `python work\weld_*.py apply`（各自 check/apply + 旧字节断言） |
| 打 IPA | `python host\deployment\package_patched_nocb.py --force`（自动删旧 IPA、校验 `EXPECT_MAIN_SHA`、叠加 `host\request\songs`） |
| 打内容包 | 先删旧 zip，再 `python host\deployment\package_container_content.py`（内部 `root=host/deployment`、`cb=host/request/cb`） |
| 签名 | `host\deployment\sign.ps1`（用户侧） |

主程序 sha256 演进（历史，便于对照回退）：`8b5fd951…` → `ab00bb24…`(FV/DO 静态焊) → `979e4506…`(BYD) → `830d7444…`(INS/闪退) → `b9913e0f…` → `65bbb30b…` → `f1f106c4…`(视频层) → `a480051b…`(角色锁 v1 + 首通异像) → `0c2e1118…` → `57213e6f…`(Designant) → **`bcaf9883…`**(角色锁 v2，当前)。

---

## 1. 主程序静态焊改总表

字节常量：`BOOL_STUB`=`20008052c0035fd6`(MOV W0,#1;RET) · `RET0`=`00008052c0035fd6`(MOV W0,#0;RET) · `PAIR_STUB`=`000080d2010080d2c0035fd6`(MOV X0,#0;MOV X1,#0;RET) · `EMPTY_RET`=`1f7d00a91f0900f9c0035fd6`(清 sret 向量 + RET) · `NOP`=`1f2003d5`。

### 1.1 FV / DO 曲包与难度解锁（`host\crack\weld_fvdo_static.py`）

目的：让 FV（Finale）与 DO（Konzetsu/Inscribed）曲包、难度**离线全开**，且**不依赖 dylib 的 BRK 命中**——直接覆写原 BRK 桩位本身（连 `000020d4` 一起去掉），所以静态生效、与注入器无关。

| 目的 | 函数/符号 | VA (fileoff) | 旧字节 → 新字节 |
| --- | --- | --- | --- |
| FV 开打门 | `FinaleUnlockState::isSongAllowedToStart` | `0x1009936CC` (`0x9936CC`) | `000020d4`+… → `BOOL_STUB` |
| FV 资产不隐藏 | `FinaleUnlockState::shouldHideFinaleSongAssets` | `0x100993668` (`0x993668`) | `000020d4`+… → `PAIR_STUB` |
| DO 前 5 挑战 | `KonzetsuManager::areFirst5ChallengesClearedForDifficulty` | `0x100AB1368` (`0xAB1368`) | 函数头 → `BOOL_STUB` |
| DO 单挑战 | `KonzetsuManager::isChallengeClearedForDifficulty` | `0x100AB14B8` (`0xAB14B8`) | 函数头 → `BOOL_STUB` |
| DO 全部挑战 | `KonzetsuManager::areAllChallengesClearedForDifficulty` | `0x100AB16F4` (`0xAB16F4`) | 函数头 → `BOOL_STUB` |
| DO 曲目不隐藏 | `KonzetsuManager::shouldHideSongAssets` | `0x100AB0958` (`0xAB0958`) | `000020d4`+… → `PAIR_STUB` |
| 封印链解锁条件(type 115) | `UnlockConditionSpecialSealKonzetsuChain::isComplete` | `0x1008214B8` (`0x8214B8`) | 函数头 → `BOOL_STUB` |
| 封印前置解锁条件(type 114) | `UnlockConditionSpecialSealKonzetsuPrechallenge::isComplete` | `0x10002ABCC` (`0x2ABCC`) | 函数头 → `BOOL_STUB` |
| Inscribed 难度显示 | `KonzetsuManager::isInscribedDifficultyRevealed` | `0x100AB1194` (`0xAB1194`) | → `BOOL_STUB`（`host\crack\apply_fvdo_patches.py`） |
| 字符串拥有判定 | `PurchaseManager::isPurchasedByString` | `0x100BE72B0` (`0xBE72B0`) | → `BOOL_STUB`（同上） |

只校验不改（`KEEP`，应为 `BOOL_STUB`）：`isPurchased(const Pack*)` `0x100BE70B8`、`isPurchased(const Song*)` `0x100BE70FC`、`isWorldUnlocked(std::string&)` `0x100BE7748`。

> ⚠ **禁止重跑 `inject.py`**：它按 `BRK_HOOKS` 会把 `000020d4` 写回这些桩位，覆盖静态焊死结果。误跑后需重跑 `host\crack\weld_fvdo_static.py apply` 并重打 IPA。
> `host\crack\stub_difflock.py`（`lock_fv=0x100993668`、`lock_do=0x100AB0958`）与 `host\crack\revert_lock_stubs.py` 是被本方案取代的早期做法，仅作历史参考。

### 1.2 BYD / INS 难度可切与"全部曲目闪退"（`host\crack\weld_byd_lock.py`、`host\crack\weld_ins_byd.py`）

| 目的 | 函数/符号 | VA (fileoff) | 旧字节 → 新字节 |
| --- | --- | --- | --- |
| BYD 难度不再被"世界未解锁"挡住 | `SongDifficulty::isSongWorldUnlocked` | `0x100BDF618` (`0xBDF618`) | → `BOOL_STUB` |
| 闪退根因：`shouldHideSongAssets` 里 `getSpecialSeal` 返回空指针后解引用 | `SongRules::shouldHideSongAssets` | `0x10091BFE0` (`0x91BFE0`) | `BL isSongSpecialMatch` → `00008052`（MOVZ W0,#0，跳过 seal 分支） |
| BYD/INS 难度永不被隐藏（否则切换被吞） | `SongDifficulty::isHidden` | `0x100BDF73C` (`0xBDF73C`) | 函数头 → `RET0` |

`.ips` 定位法：`frame0 imageOffset`（十进制）= 主程序 fileoff → `fileoff + 0x100000000` = 崩溃 VA；本次 `9551856` = `0x91BFF0`，落在同函数内。

### 1.3 流速上限与强制剧情（`host\crack\weld_speed_story.py`）

| 目的 | VA (fileoff) | 旧 → 新 | 说明 |
| --- | --- | --- | --- |
| 流速上限高 16 位 | `0x1017A8B4` (`0x17A8B4`) | `09050151` → `ebff9f52` | `MOVZ W11,#0xFFFF` |
| 流速下限 | `0x1017A8B8` (`0x17A8B8`) | `1f290071` → `1f010071` | `CMP W8,#0` |
| 兜底值 | `0x1017A8BC` (`0x17A8BC`) | `4a018052` → `0a008052` | `MOVZ W10,#0` |
| 上限拼成 INT_MAX | `0x1017A8C0` (`0x17A8C0`) | `2b088052` → `ebffaf72` | `MOVK W11,#0x7FFF,LSL#16` |
| 取消 65 窗口钳制 | `0x1017A8D0` (`0x17A8D0`) | `3fd90031` → `ff030071` | `CMP WZR,WZR,#0` |
| “−”按钮下限（两处） | `0x1017A57C` (`0x17A57C`)、`0x1017A594` (`0x17A594`) | `5f2b0071` → `5f030071` | 下限 → 0 |
| 不触发曲包前半剧情 | `KonzetsuManager::shouldTriggerPackFirstHalfStory` `0x100AAFA10` | → `MOV W0,#0;RET` | |
| 不触发 Lament Rain 剧情 | `willLamentRainStoryShow` `0x1001839D4` | 同上 | |
| 不触发 Insight Altered 剧情 | `shouldInsightAlteredStoryShow` `0x100183B0C` | 同上 | |
| 不触发 UndyingMacula 剧情 | `UndyingMaculaPuzzleManager::shouldInsightStoryTriggerActivate` `0x100098104` | 同上 | |
| 不触发 Arcahv 剧情 | `MapScene::triggerArcahvStory` `0x100835478` | → `RET` | |
| 不弹终章一次性提示 | `FinaleStoryOneShotPromptLayer::show` `0x100ABBDC8` | → `RET` | |

### 1.4 教程与阶段任务屏蔽（`host\crack\weld_no_tutorial_mission.py`）

目的：只屏蔽**触发**，不删功能代码。

| 目的 | 函数/符号 | VA (fileoff) | 旧 → 新 |
| --- | --- | --- | --- |
| 首启点开始游戏不再自动进教程 | `gotoSongSelect` 内 `TBZ(tutorialSeen)` | `0x10006B280` (`0x6B280`) | `00010036` → `NOP` |
| 曲包页首次教程 | `PackListLayer::showFirstTimeTutorialIfNeeded` | `0x1009EA118` (`0x9EA118`) | → `RET` |
| 不弹进阶教程 | `SongSelectScene::showAdvancedTutorialDialogIfNeeded` | `0x100C16EAC` (`0xC16EAC`) | → `MOV W0,#0;RET` |
| 阶段任务数据不加载 | `MissionManager::loadMissions` | `0x1008FA6C0` (`0x8FA6C0`) | → `RET` |
| 阶段任务节点触发屏蔽 | `MainMenuScene::updateEventAndMissionNodes` | `0x10005E614` (`0x5E614`) | → `RET` |

> ⚠ **不要**把 `MainMenuScene::setupEventAndMissionNodes`(`0x5E188`) 整函数做掉：`updateNetworkStatus` 会解引用 `getChildByName("missions_node")` 的结果而不判空（`0x10005EF14` → `0x10005EF3C`）⇒ 崩。

### 1.5 进曲/演出视频层安全（`host\crack\weld_video_layer_safe.py`、`host\crack\weld_no_video_intro.py`）

目的：Designant. 等曲目进曲崩在 `CCVideoLayerIOS::update(float)`（PAC 失败，`[X19+0x4A0]` 是未被赋值的堆垃圾）——包内没有随包视频，`init` 早退但 `update` 仍在跑。

| 目的 | VA (fileoff) | 旧 → 新 |
| --- | --- | --- |
| `update`：`LDR X20,[X19,#0x4A0]` | `0x100857ED0` (`0x857ED0`) | `745242f9` → `140080d2`(MOVZ X20,#0) |
| `update`：`LDR X0,[X19,#0x4A0]` | `0x100857EF4` (`0x857EF4`) | `605242f9` → `000080d2` |
| `update`：`LDR X0,[X19,#0x4A0]` | `0x100857F34` (`0x857F34`) | `605242f9` → `000080d2` |
| 不创建进曲演出层 `KonzetsuSongIntroLayer` | `0x100C33218` (`0xC33218`)、`0x100C33498` (`0xC33498`) | → `000080d2` |

> 先跑 `host\crack\weld_video_layer_safe.py`，若仍有进曲黑屏/崩溃再看 `host\crack\weld_no_video_intro.py`（同族入口，脚本内自带断言）。

### 1.6 角色（搭档）全解锁（`host\crack\weld_char_own.py` + `host\crack\weld_char_own2.py`）

对象模型：`CharacterManager` `[+0x00]` = 已拥有 id 的 `std::vector<int>`，`[+0x18]` = 全部 `Character*` 向量，`[+0x30]` = id→条目字典，`[+0x68]` = 兜底项。界面里**大量代码直接读 `[manager+0]` 做成员判定**（`BL unk_10001DDF0` 后 `LDP Xa,Xb,[X0]`），所以只改 getter 不够——必须同时把内联判定改成"恒已拥有"。

第一层：四个 getter（`host\crack\weld_char_own.py`）

| 目的 | VA (fileoff) | 旧 → 新 |
| --- | --- | --- |
| `getUnownedCharacters` 恒空 | `0x100A01464` (`0xA01464`) | → `EMPTY_RET` |
| `getOwnedButLockedCharacters` 恒空 | `0x100A01300` (`0xA01300`) | → `EMPTY_RET` |
| `getObtainedCharacters` 循环比较 | `0x100A016F4` (`0xA016F4`) | `9f010b6b` → `9f010c6b`（`CMP W12,W12`） |
| `getObtainedCharacters` 跳过空向量分支 | `0x100A01710` (`0xA01710`) | `e0000054` → `NOP` |
| `getAllPartnerSelectCharacters` 同上 | `0x100A009CC` (`0xA009CC`) | `0a010037` → `NOP` |

第二层：界面内联成员判定（`host\crack\weld_char_own2.py`）

| 目的 | VA (fileoff) | 旧 → 新 |
| --- | --- | --- |
| `PartnerCell::setupWithCharacter` 循环首元素即命中 | `0x100100EB0` (`0x100EB0`) | `3f01086b` → `3f01096b`（`CMP W9,W9`） |
| 同上：去掉"未拥有"结论（传给 vtable+0x150） | `0x100100ED0` (`0x100ED0`) | `f7179f1a` → `17008052`（`MOVZ W23,#0`） |
| 同上：三处"已拥有"标志 | `0x100100F0C`/`0x100100F38`/`0x100100F64` (`0x100F0C`/`0x100F38`/`0x100F64`) | `e8079f1a` → `28008052`（`MOVZ W8,#1`） |
| `PartnerSelectDialogASide::updateCharacterInfo` 同判定 | `0x1000C8B90` (`0xC8B90`) | `3f01086b` → `3f01096b` |
| `PartnerSelectDialogASide::updateSelectedCharacterState` 同判定 | `0x1000CB184` (`0xCB184`) | `3f01086b` → `3f01096b` |

> 仍有个别角色锁着（或"选不上"）时的第三/四层：
> - `host\crack\weld_char_own3.py`（13 处关键门控，含**选择动作本身**）：`0x101518` `PartnerCell::setSelected(bool,bool)` 内的拥有判定是主嫌疑（未拥有时 setSelected 不生效 ⇒ "锁图标没了但点不上"）、`0xCB778`(updateLevelingButtonAndCosts)、`0xCFBA0`(dialogClosePressed)、`0xD2E30`(returnedFromDetails)、`0xF0900`/`0xF0D18`/`0xF3DAC`(BSide update*)、`0xF6DE0`/`0xF6F54`/`0xF70C8`/`0xF726C`/`0xF72D4`/`0xF8538`(BSide presentTutorialOrGuide)。
> - `host\crack\weld_char_own4.py`（**批量**）：用 `host\crack\scan\own_gates.py` 枚举 `BL unk_10001DDF0` + `LDP Xa,Xb,[X0]` + `LDR Wt,[Xa]` + `CMP Wt,Wm` 模式，把 `0xC0000–0x110000`（搭档/角色界面）内**全部**该类 CMP 改成自比较。共 189 个门控，其中 173 个被批量改掉、16 个此前已是自比较。
> - 全部手法同一：`SUBS WZR,Wt,Wm` → `SUBS WZR,Wt,Wt`（Rm := Rn）。
> 参考：`LDRB Wt,[Xn,#0x120]`（锁定/封印位）在 `0x1000C0000-0x100110000` 内 **0 处** ⇒ 界面锁定真源是"拥有向量成员判定"，不是 `+0x120`。
> 另一条独立线索："Skill and stats are inactive"（中文界面显示「技能和能力值均未激活」）cstring @`0x10137D171`，唯一引用点 `0x1000C8DB8`（在 `PartnerSelectDialogASide::updateCharacterInfo` `0x1000C8B4C` 内）；判据 `W27 = [[0x1016781D8]→+0x78]→+0xC`（封印/状态字节，`==1` 时走 "[SKILL]SEALED" + `layouts/character/v2.1/lock-icon.png`，`==0` 时走 "SKILL ACTIVE"）。

### 1.7 首通异像通路移除（`host\crack\weld_no_firstplay_anomaly.py`）

目的：只保留"特定角色进特定曲目"触发异像的通路，去掉"首次进入"触发。

| 目的 | 对象 | VA (fileoff) | 旧 → 新 |
| --- | --- | --- | --- |
| DreadArea 首通 | `SpecialSceneDreadAreaFirstPlay::create` 两处调用点 | `0x100C2542C`/`0x100C35084` (`0xC2542C`/`0xC35084`) | `20008052` → `000080d2`（参数 1→0） |
| 首通标志写入 | `SongSelectScene::startGameScene` 内 `STRB W20,[X21,#0x2B4]` | `0x100C129E4` (`0xC129E4`) | `b4d20a39` → `bfd20a39`（存 WZR） |
| Ember 分派布尔 | `GameScene::calculateSpecialScene` ember 分支 | `0x100CA6A4C` (`0xCA6A4C`) | `CSET W0,NE` → `000080d2` |
| CataclysmCry 首通判定 | `SpecialSceneCataclysmCryFirstPlay::calculateIsValidAnomalyPlay` | `0x100BD5608` (`0xBD5608`) | → `RET0` |
| DeinosPhainein 首通判定 | `SpecialSceneDeinosPhaineinFirstPlay::calculateIsValidAnomalyPlay` | `0x100C6E69C` (`0xC6E69C`) | → `RET0` |
| Designant. 首通变体 | `SpecialSceneDesignantChallenge` 创建前 `LDRB W1,[X19,#0x2B4]`（SpecialSceneModifier 的首通标志当 mode） | `0x100A98740` (`0xA98740`) | `61d24a39` → `21008052`（`MOV W1,#0`） |
| Designant. 首通异像项（**真凶**） | `unk_1009F9310`（songId=="designant" 的 mask 计算）内的 `EOR W8,W8,#1` | `0x1009F9428` (`0x9F9428`) | `08010052` → `08008052`（`MOVZ W8,#0`） |

Designant. 的机制（供换版本时对照）：`SpecialSceneDesignantChallenge::create(std::string songId,int mode)` @`0x100A98890` → `unk_1009F9280(mode, songId)` 求变体存 `[+0x2B8]`（0..3）；`mode bit0=1 ⇒ 变体 3`（"关暂停/关重试/隐藏曲目信息"的首通表现）；mask = `unk_1009F9310(0,songId)`：
- songId=="designant" → 走 `0x1009F93DC`：`mask = 角色掩码 | (state!=0 ? 0 : (封印位 ^ 1))`。**`封印位 ^ 1` 就是"谁都触发"的首通项**（封印状态未推进时恒为 1）⇒ 改成 `MOVZ W8,#0` 即"只保留角色触发"。
- songId=="lamentrain" → `unk_1009F9494`（角色 id `0x4E`=78）。
角色掩码 `unk_1009F943C` = 当前角色 id == `0x48`(72) ∧ `[[0x1016781D8]→+0x78]→+0xC == 1` ∧ `[[0x1016781D8]→+0x28]→+0x96` bit0。
变体 2 = `setupFloatingChallengeHp`（异像表现：背景走视频通路 + 谱面按 `arc(...,none,designant)` 渲染红键；包内无视频 ⇒ 黑背景，`3.aff` 里 140269ms 处有 `scenecontrol`/`camera` 联动）。这些角色通路**未动**。

Designant. 的机制（供换版本时对照）：`SpecialSceneDesignantChallenge::create(std::string songId,int mode)` @`0x100A98890` → `unk_1009F9280(mode, songId)` 求变体存 `[+0x2B8]`（0..3）；`mode bit0=1 ⇒ 变体 3`（"关暂停/关重试/隐藏曲目信息"的首通表现）；角色通路来自 `unk_1009F9310(0,songId)`：songId=="designant" → `unk_1009F943C`（角色 id `0x48`=72 且 `[global+0x78]→[+0xC]==1`），"lamentrain" → `unk_1009F9494`（角色 id `0x4E`=78）。这两条**未动**。

> 同类 `*FirstPlay` 场景：`SpecialSceneLamentRain`（角色通路，故意保留）、`SpecialSceneSacrosanctFirstPlay`（首通表现走 `showToBeContinued` `0x100C017D0`）、`UndyingMacula`、`AstralQuant`——**尚未定位/未焊**，若真机仍见首通异像按同法补。

---

## 2. 数据侧改动

| 目标 | 改动 | 手法 / 脚本 |
| --- | --- | --- |
| 去掉"0 残片解锁" | `songs/unlocks` 写成空表：app 包 `{"unlocks":[]}`（14 B，紧凑）；内容包分片 `host\request\cb\bundle_0.cb` 同内容等长覆盖（149,699 B，sha256 `7b99971c…`）；`host\deployment\cb\active\songs\unlocks` 同步 | `host\request\unlocks_direct.py`（三处双写 + 三份 meta 同步） |
| 曲目可见/难度可见 | `songs/songlist` 的 `remote_dl` / `world_unlock` / `hidden_until` 等字段 | `host\request\restore_songlist_meta.py`、`host\request\songlist_basepack.py` |
| Lament Rain 预览无声 | 把 cb 里 `songs/dl_lamentrain/preview.ogg`（586,247 B，sha256 `8f2d0a27…`）复制为 `host\request\songs\lamentrain\preview.ogg` | 预览路径由 `Song::getAudioFilepathForDifficultyClass`（`"_preview.ogg"`@`0x10138683E`→`0x10084FC20`、`"/preview.ogg"`@`0x10138684B`→`0x10084FC6C`）+ songlist 的 `audioPreview`/`audioPreviewEnd`(ms) 决定 |
| ~~`char/characters.json` 全解锁~~ | **无效改动（反面教训）**：`is_available` 仅 1 处 cstring（商店/曲包链用）；`is_previewable`/`uncap_visible_req`/`is_tairitsu` 在二进制里**根本不存在**；唯一读取器 `0x1009FFB2C` 不读这些键。拥有关系只在存档/服务端数据里 | 撤销，不再改 |

内容包（cb）机制要点：

- `cb/active/<path>` **优先于** app 包同路径（cocos2d FileUtils 前置搜索路径）；`cbBypass` / `externalCb` 默认 YES，会拦掉 wipe/dispatch ⇒ 热更新不会覆盖我们的 `songs/unlocks`；**若把它们关掉，更新会覆盖**。
- 分片必须**等长覆盖**：先 `host\crack\strip_pad.py` 去 padding，改完 `host\request\fix_meta_cb.py` 回填并同步三份 meta（`meta.cb` / `bundle.json` / 分片内 meta 的 sha256+大小）。
- IPA 内**不含** `.cb`；容器包独立交付（`Arc-Exercise-content-7.0.260-container-ready.zip`）。
- `host\request\songs`（2.2 GB）是打 IPA 的叠加源，`host\request\cb`（870 MB）是打内容包的唯一源——删了就失去离线重建能力。

---

## 3. 每轮固定动作（checklist）

1. 改主程序：`python work\<weld 脚本>.py check` → `apply`（脚本会自动同步 `EXPECT_MAIN_SHA`）。
2. 打 IPA：`python host\deployment\package_patched_nocb.py --force`（旧 IPA 自动删；若旧 `-signed.ipa` 被签名工具占用，脚本只会警告跳过，不再中断）。
3. 包内核验：`Payload/Arc-mobile.app/Arc-mobile` 的 sha256 = `EXPECT_MAIN_SHA`；逐点回读改后字节；条目数；`zipfile.testzip()`；`crc_verified`。
4. 交付口径：主程序 sha256、IPA 字节数 + sha256 + 条目数、回退路径（当前无磁盘备份，仅 `host\request\orig-data` 三份改前数据）。
5. 内容包有改动时才重打 `package_container_content.py`（先删旧 zip）。

---

## 4. 换版本时的定位套路（工具都在 `work\`）

| 需求 | 工具 | 用法 |
| --- | --- | --- |
| 取符号表 | `host\crack\scan\oldtrie.py`、`host\crack\scan\trie_exports.py`、`host\crack\scan\macho_syms.py` | 输出到 `sym_all.txt` / `all_names.txt` |
| 反汇编函数 | `host\crack\ida_func.py <bin> <out> [--max=N] <VA...>` | `=0xVA` = 从该地址固定条数；`0xVA` = 整个函数 |
| 反汇编片段 | `host\crack\ida_disasm.py <bin> <VA>` | 前后 ±6 条 |
| 裸字节/编码 | `host\crack\scan\a64.py <start-end> ...` | 用于写断言旧字节 |
| 字符串→引用 | `host\crack\ida_refscan2.py <bin> <out> <string...>`、`host\crack\scan\xref_str.py` | 找 UI 文案/JSON key 的读取点 |
| ADRP+ADD 引用 | `host\crack\scan\refs_va.py <bin> <VA...>` | 找指向某函数/数据的代码 |
| 调用点反查 | `host\crack\scan\xref_call.py <bin> <out> <VA...>` | BL/B/B.cond 全部命中（有少量误报） |
| 内联成员判定循环 | `host\crack\scan\own_loops.py <bin> [lo] [hi]` | 找 `LDR Wt,[Xn] ; CMP Wt,Wm`，用于把判定改成自比较 |
| 空指针/崩溃定位 | `.ips` 的 `imageOffset`（十进制）= fileoff | 例：`9551856` = `0x91BFF0` |

**IDA 坑（血泪）**：`host\crack\scan` 或 `host\deployment` 下若残留 `*.id0/*.id1/*.id2/*.nam/*.til`，`idapro.open_database(path, False)` 会复用旧库 ⇒ `get_wide_byte` 返回 `0xff` ⇒ 反汇编整段 `???`。**先把二进制复制成新文件名**再开库（脚本里已按此习惯），并且别用自动分析（会崩）。

---

## 5. 已知坑 / 禁止项

- 不要重跑 `inject.py`（会重装 BRK，覆盖 1.1 的静态桩）。
- 不要把 `MainMenuScene::setupEventAndMissionNodes`(`0x5E188`) 整函数做掉（`missions_node` 无空判）。
- 静态焊改是**等长覆写**：改前必须断言旧字节；跨版本后旧字节一定不同 ⇒ 必须先重新定位再改断言。
- 打包脚本只做 `EXPECT_MAIN_SHA` 断言 + 叠加 `host\request\songs` + 排除杂物（`cb_overlap` 724 / `ida_db` 5 / `code_signature` 1 / `sc_info` 7 / `plugins` 37），**不施加任何静态补丁**。
- `host\crack\backup` 已删除（回退能力随之消失）；仅保留 `host\request\orig-data\{unlocks.orig.json, songlist.pre-hidden.json, characters.json.orig}`。

---

## 6. 未完成 / 待验证

- 角色锁 v2 真机验证：界面是否全部按"已拥有"呈现并可装配；仍有残留锁 → 按 1.6 的未覆盖清单补。
- 首通异像：`Sacrosanct` / `UndyingMacula` / `AstralQuant` 首通支路未定位；Designant. 首通是否真消失待真机确认。
- `preview.ogg` 全量补齐（`host\request\songs` 里 532 首缺预览，当前只补了 `lamentrain`）。
- 热更新关闭 `cbBypass`/`externalCb` 的场景下，`songs/unlocks` 会被覆盖 —— 未测。
