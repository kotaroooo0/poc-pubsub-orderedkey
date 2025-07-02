# Google Cloud Pub/Sub OrderedKey 挙動検証

Google Cloud Pub/SubのOrderedKey機能の実際の挙動を検証するためのDartプロジェクトです。

## 検証目的

OrderedKeyを使用した場合の以下の挙動を確認します：

**検証したい仮説:**
- OrderedKeyは「配信順序」と「ACK順序」を保証する
- しかし、ACK完了前に次のメッセージがpull可能かどうかは不明

**具体的なシナリオ:**
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
gcloud pubsub topics create test-ordered-topic \
  --message-ordering

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

同一OrderedKeyで複数のメッセージを連続送信します。

### 2. Subscriberの実行

```bash
dart run bin/subscriber.dart
```

3つの並列Subscriberが起動し、以下の動作を行います：
- メッセージをpull
- 3-8秒間のランダムスリープ（処理時間をシミュレート）
- メッセージをACK

## 期待される結果

### パターンA（厳密な順序保証の場合）
```
[Subscriber-1] Pulled: Message A at 10:00:00
[Subscriber-2] Waiting... (Message Bはpull不可)
[Subscriber-3] Waiting... (Message Bはpull不可)
[Subscriber-1] ACKing: Message A at 10:00:05
[Subscriber-2] Pulled: Message B at 10:00:05
[Subscriber-2] ACKing: Message B at 10:00:10
```

### パターンB（配信順序のみ保証の場合）
```
[Subscriber-1] Pulled: Message A at 10:00:00
[Subscriber-2] Pulled: Message B at 10:00:00  # AのACK前でも可能
[Subscriber-1] ACKing: Message A at 10:00:05
[Subscriber-2] ACKing: Message B at 10:00:05
```

## 注意事項

- 実際のGoogle Cloud環境を使用するため、料金が発生する可能性があります
- テスト後はリソースのクリーンアップを忘れずに行ってください
- OrderedKeyは同一Subscription内でのみ有効です

## クリーンアップ

```bash
# Subscriptionの削除
gcloud pubsub subscriptions delete test-ordered-subscription

# Topicの削除
gcloud pubsub topics delete test-ordered-topic
