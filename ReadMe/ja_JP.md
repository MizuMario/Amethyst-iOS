# Angel Aura Amethyst (iOS)

[![Development build](https://github.com/AngelAuraMC/Amethyst-iOS/actions/workflows/development.yml/badge.svg?branch=main)](https://github.com/MizuMario/Amethyst-iOS/actions/workflows/development.yml)

## 警告

このリポジトリは(勝手に)フォークして、一部要素を変更してビルドしているものです。

## Amethystとは

Amethystは iOS/Android 向けMinecraft JEのランチャーです。ベースはzhuoweiさんの [Boardwalk](https://github.com/zhuowei/Boardwalk)となっています。

* おおよそのバージョンに対応しています(Vulkanを使う新しいバージョンから、初期のベータ版まで)
* おおよそのModLoaderの導入やModのダウンロードも対応しています
* カスタマイズ可能な画面上の操作、キーボードとマウスへの対応、ゲームコントローラーへの対応
* ちゃんとマイクロソフトアカウントにサインインできます(開発者は情報を一切確認できませんからね)
* その他諸々

このリポジトリはiOS版です。Android版については[こちら](https://github.com/AngelAuraMC/Amethyst-Android)を参照してください

## はじめ方

[Amethyst wiki](https://wiki.angelauramc.dev/wiki/getting_started/INSTALL.html#ios)には、インストールやセットアップ、プレイ方法に関する詳細なドキュメントが用意されています！すぐにインストールしたいという方のために、基本的な手順を以下にまとめてあります。

しかしながら、このリポジトリはUIの要素が書き直しているためやや異なる内容があります。

### 要件

最低要件としては以下のデバイスで **iOS 14.0** 以降を実行している環境です
* iPhone 6s 以降
* iPad (第5世代) 以降
* iPad Air (第2世代) 以降
* iPad mini (第4世代) 以降
* iPad Pro (大体のモデル)
* iPod touch (第7世代)

しかしながら、推奨要件は以下のデバイスで  **iOS 14.0** 以降を実行している環境で
* iPhone XS 以降, iPhone XRやiPhone SE(第2世代)も含みます
* iPad (第10世代) 以降
* iPad Air (第4世代) 以降
* iPad mini (第6世代) 以降
* iPad Pro (大体のモデル。ただし、9.7インチは除く)

推奨端末を使用すると、その他の対応端末と比べて、よりスムーズで快適なゲームプレイ体験が得られます。

* iOS 17.x ~ iOS 27.x は対応こそしていますが、一部バージョンはJITを用いるためにPCが必要となる場合があります。詳しくは[こちら](https://wiki.angelauramc.dev/wiki/faq/ios/JIT.html#what-are-the-methods-to-enable-jit)を参照してください

### アプリをサイドロード

Amethystは色々な方法でサイドロードできます。おすすめは[TrollStore](https://github.com/opa334/TrollStore)です。もしも、対応するiOSバージョンならば、勝手にJITが有効化したりメモリ上限(対応端末のみ)が引き上げられます。
もしも、使えないならば[AltStore](https://altstore.io) と [SideStore](https://sidestore.io) がおすすめです。
* AltStoreやSideStoreを使う場合は自動的にJITやメモリ上限引き上げができる訳ではないので、別途で有効化をお願いします
* Amethystはちゃんと信頼できるところからインストールしてください。さもなければ、えらい目に遭うことがあるかもです。
* Jailbreak もおすすめです。TrollStoreと同じ感じになります。しかし、常日頃から使うデバイスであれば推奨しません。
* 一応LiveContainerでも動作することは確認しています。

> [!メモメモ]
> これは非公式ビルドです。それ即ちそう言う事です。フォークした人はそう言う情報を収集するような機能や考えは実装していませんが、心配ならば使わないことを推奨します。

### アプリのインストール

#### Release build (TrollStore)

1. [Releases](https://github.com/AngelAuraMC/Amethyst-iOS/releases)からIPAファイルをダウンロード
2. TrollStoreでインスコ

#### Release build (AltStore/SideStore)

1. [Releases](https://github.com/AngelAuraMC/Amethyst-iOS/releases)からIPAファイルをダウンロード
2. 各ストアでインスコ

> [!Note]
ソースは作る気力はないのでアップデート毎にIPAファイルを落としてください


#### Nightly builds

*結構不安定な傾向にあるので気をつけてください*

1. Amethystを[Actions tab](https://github.com/AngelAuraMC/Amethyst-iOS/actions)からダウンロード
2. 各ストアでインスコ

### JITの有効化
Amethystは、エンドユーザーが実用的な速度で利用できるよう、「JIT（Just-In-Timeコンパイル）」を活用しています。iOSでは、アプリケーションがデバッグモードでない限りJITはサポートされないため、これを利用するには回避策を講じる必要があります。環境に最適な方法でやってみてください

| Application         | AltStore | SideStore | StikDebug | TrollStore | Jitterbug          | Jailbroken |
|---------------------|----------|-----------|-----------|------------|--------------------|------------|
| Requires ext-device | Yes      | Yes (#)   | Yes (#)   | No         | If VPN unavailable | No         |
| Requires Wi-Fi      | Yes      | Yes (#)   | Yes (#)   | No         | Yes                | No         |
| Auto enabled        | Yes (*)  | No        | Yes       | Yes        | No                 | Yes        |

(*) AltServer が同一ネットワークで動いている場合
(#) 初回のみ

## Contributors

Amethystは素晴らしいプロジェクトであり、驚くほど安定しています。これもひとえに、プロジェクトを支え、貢献してくださったコミュニティの皆さんのおかげです！特に貢献してくださった方々をいくつか挙げます。

@crystall1nedev - Project manager, iOS port developer  
@khanhduytran0 - iOS port developer  
@artdeell  
@Mathius-Boulay  
@zhuowei  
@jkcoxson
@Diatrus

## サードパーティ製コンポーネントおよびそのライセンス

- [Caciocavallo](https://github.com/PojavLauncherTeam/caciocavallo): [GNU GPLv2 License](https://github.com/PojavLauncherTeam/caciocavallo/blob/master/LICENSE).
* [jsr305](https://code.google.com/p/jsr-305): [3-Clause BSD License](http://opensource.org/licenses/BSD-3-Clause).
* [Boardwalk](https://github.com/zhuowei/Boardwalk): [Apache 2.0 License](https://github.com/zhuowei/Boardwalk/blob/master/LICENSE)
* [GL4ES](https://github.com/ptitSeb/gl4es) by @lunixbochs @ptitSeb: [MIT License](https://github.com/ptitSeb/gl4es/blob/master/LICENSE).
* [Mesa 3D Graphics Library](https://gitlab.freedesktop.org/mesa/mesa): [MIT License](https://docs.mesa3d.org/license.html).
* [MetalANGLE](https://github.com/khanhduytran0/metalangle) by @kakashidinho and ANGLE team: [BSD 2.0 License](https://github.com/kakashidinho/metalangle/blob/master/LICENSE).
* [MoltenVK](https://github.com/KhronosGroup/MoltenVK): [Apache 2.0 License](https://github.com/KhronosGroup/MoltenVK/blob/master/LICENSE).
* [openal-soft](https://github.com/kcat/openal-soft): [LGPLv2 License](https://github.com/kcat/openal-soft/blob/master/COPYING).
* [Azul Zulu JDK](https://www.azul.com/downloads/?package=jdk): [GNU GPLv2 License](https://openjdk.java.net/legal/gplv2+ce.html).
* [LWJGL3](https://github.com/PojavLauncherTeam/lwjgl3): [BSD-3 License](https://github.com/LWJGL/lwjgl3/blob/master/LICENSE.md).
* [LWJGLX](https://github.com/PojavLauncherTeam/lwjglx) (LWJGL2 API compatibility layer for LWJGL3): unknown license.
* [DBNumberedSlider](https://github.com/khanhduytran0/DBNumberedSlider): [Apache 2.0 License](https://github.com/immago/DBNumberedSlider/blob/master/LICENSE)
* [fishhook](https://github.com/khanhduytran0/fishhook): [BSD-3 License](https://github.com/facebook/fishhook/blob/main/LICENSE).
* [shaderc](https://github.com/khanhduytran0/shaderc) (used by Vulkan rendering mods): [Apache 2.0 License](https://github.com/google/shaderc/blob/main/LICENSE).
* [NRFileManager](https://github.com/mozilla-mobile/firefox-ios/tree/b2f89ac40835c5988a1a3eb642982544e00f0f90/ThirdParty/NRFileManager): [MPL-2.0 License](https://www.mozilla.org/en-US/MPL/2.0)
* [AltKit](https://github.com/rileytestut/AltKit)
* [UnzipKit](https://github.com/abbeycode/UnzipKit): [BSD-2 License](https://github.com/abbeycode/UnzipKit/blob/master/LICENSE).
* [DyldDeNeuralyzer](https://github.com/xpn/DyldDeNeuralyzer): bypasses Library Validation for loading external runtime
* Thanks to [MCHeads](https://mc-heads.net) for providing Minecraft avatars.
