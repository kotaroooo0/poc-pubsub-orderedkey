# Google Cloud Pub/Sub OrderedKey 挙動検証

Google Cloud Pub/SubのOrderedKey機能の実際の挙動を検証するためのDartプロジェクトです。

## 検証目的

OrderedKeyを使用した場合の以下の挙動を確認します：

**検証したい仮説:**
- OrderedKeyは「配信順序」を保証する
- しかし、ACK完了前に次のメッセージがpull可能かどうかは不明

**具体的なシナリオ:**

以下のどちらになるのか不明なので検証する

```
同じOrderedKeyでメッセージA、Bを送信した場合：

パターン1（厳密な順序保証）:
1. Subscriber1がメッセージAをpull
2. メッセージBは他のSubscriberがpull不可（AのACK待ち）
3. Subscriber1がメッセージAをACK
4. Subscriber2がメッセージBをpull可能になる

パターン2（配信順序のみ保証）:
1. Subscriber1がメッセージAをpull
2. Subscriber2がメッセージBをpull可能（AのACK前でも）
3. 各Subscriberが独立してACK
```

## プロジェクト構成

```
poc-pubsub-orderedkey/
├── bin/
│   ├── publisher.dart       # OrderedKey付きメッセージ送信
│   └── subscriber.dart      # 並列Subscriber（スリープ→ACK）
├── lib/
│   └── config.dart         # GCP設定
├── pubspec.yaml
└── README.md
```

## 前提条件

1. Google Cloud Projectの作成
2. Pub/Sub APIの有効化
3. Service Accountの作成と認証情報の設定
4. Dart SDKのインストール

## セットアップ

### 1. GCPリソースの作成

```bash
# プロジェクトIDを設定
export PROJECT_ID="your-project-id"

# Topicの作成（OrderedKey有効）
gcloud pubsub topics create test-ordered-topic

# Subscriptionの作成（OrderedKey有効）
gcloud pubsub subscriptions create test-ordered-subscription \
  --topic=test-ordered-topic \
  --enable-message-ordering
```

### 2. 認証設定

```bash
# Application Default Credentials (ADC) を設定
gcloud auth application-default login

# プロジェクトを設定
gcloud config set project YOUR_PROJECT_ID
```

### 3. 環境変数設定

`.env`ファイルを作成：

```
PROJECT_ID=your-project-id
TOPIC_NAME=test-ordered-topic
SUBSCRIPTION_NAME=test-ordered-subscription
```

### 4. 依存関係のインストール

```bash
dart pub get
```

## 実行方法

### 1. Publisherの実行

```bash
dart run bin/publisher.dart
```

**全15個のメッセージを同一OrderedKey（'test-key-1'）で送信**し、3並列Subscriberの競合状況を検証します。

### 2. Subscriberの実行

```bash
# デフォルト設定（3 subscribers, maxMessages=3）
dart run bin/subscriber.dart

# カスタム設定
dart run bin/subscriber.dart --subscribers=5 --max-messages=10

# 短縮オプション
dart run bin/subscriber.dart -s 2 -m 1

# ヘルプ表示
dart run bin/subscriber.dart --help
```

#### オプション
- `--subscribers` / `-s`: 並列Subscriber数（1-20、デフォルト: 3）
- `--max-messages` / `-m`: 1回のpullで取得する最大メッセージ数（1-100、デフォルト: 3）
- `--help` / `-h`: ヘルプ表示

#### 動作内容
指定された数の並列Subscriberが起動し、以下の動作を行います：
- **バッチ処理**: 指定された`maxMessages`で複数メッセージを同時pull
- 受信した全メッセージを順次処理してまとめてACK
- 指定された時間のスリープ（処理時間をシミュレート）
- **詳細なログ出力**:
  - 📦 BATCH PULLED: バッチ受信メッセージ数表示
  - 🔄 Processing: 各メッセージの処理状況（N/M形式）
  - ✅ Processed: 個別メッセージ処理完了
  - 🎯 BATCH ACKED: バッチ全体のACK完了
  - ⏱️ バッチ処理時間の計測
  - ═══ 区切り線で各バッチを明確化

## 📊 検証結果

### 🔬 テスト環境
- **メッセージ数**: 15個
- **Subscriber**: 3並列
- **処理時間**: 0-5秒のランダムスリープ

### ✅ 検証結果まとめ

| シナリオ      | OrderingKey                                                          | 処理方式       | 結果                                                                                                                   |
| ------------- | -------------------------------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **シナリオ1** | 全て同じKey + maxMessages=1                                          | **直列処理**   | ✅ 前のメッセージのACK完了まで次のメッセージはブロック                                                                  |
| **シナリオ2** | 全て異なるKey + maxMessages=1                                        | **3並列処理**  | ✅ OrderingKey指定なしと同様の並列処理                                                                                  |
| **シナリオ3** | 2つのKeyグループ + maxMessages=1<br/>(1-5番目: Key1, 6-15番目: Key2) | **2並列処理**  | ✅ 各KeyグループごとにACK順序保証                                                                                       |
| **シナリオ4** | 全て同じKey + maxMessages=3                                          | **バッチ処理** | 🆕 前のメッセージのACK完了まで次のメッセージはブロック。ただし、同一Subscriber内では同じOrderingKeyを複数同時pull可能。 |

### 🎯 重要な発見

**OrderedKeyは「Subscriber単位での排他制御」を行う**

#### 🔍 詳細な挙動分析

**1. 同一Subscriber内でのバッチ処理**
- ✅ **maxMessages=3**: 同じOrderedKeyのメッセージを複数同時にpull可能
- ✅ **順次処理**: pullした複数メッセージを順番に処理
- ✅ **バッチACK**: 全メッセージ処理完了後にまとめてACK

**2. 同じOrderingKeyのメッセージに対するSubscriber間の排他制御**
- ✅ **厳密な排他**: あるSubscriberAが複数メッセージをpullしている間、他のSubscriberはpull不可
- ✅ **ACK待ち**: SubscriberAが全メッセージをACKするまで、他のSubscriberは待機
- ✅ **順序保証**: Subscriber間では厳密な順序を保証

## 期待される結果（検証前の仮説）

### パターンA（厳密な順序保証の場合）- ✅ 検証で確認
```
[Subscriber-1] Pulled: Message A at 10:00:00
[Subscriber-2] Waiting... (Message Bはpull不可)
[Subscriber-3] Waiting... (Message Bはpull不可)
[Subscriber-1] ACKing: Message A at 10:00:05
[Subscriber-2] Pulled: Message B at 10:00:05
[Subscriber-2] ACKing: Message B at 10:00:10
```

### パターンB（配信順序のみ保証の場合）- ❌ 検証で否定
```
[Subscriber-1] Pulled: Message A at 10:00:00
[Subscriber-2] Pulled: Message B at 10:00:00  # AのACK前でも可能
[Subscriber-1] ACKing: Message A at 10:00:05
[Subscriber-2] ACKing: Message B at 10:00:05
```
