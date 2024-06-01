# Recommended to run this before building.
flutter clean; 

# Build + ENV variable definition for the Telegram bot API key (replace with actual secret)
flutter build apk --dart-define=TELEGRAM_JUAN_BOT_API_KEY=<replace_actual_secret_here>;