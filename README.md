# 👗 Smart Wardrobe AI

Smart Wardrobe AI is a next-generation digital closet assistant built with **Flutter** and powered by **Google Gemini 1.5 Flash**. It helps users organize their clothing collections and provides intelligent outfit recommendations by analyzing real-time local weather, user mood, and travel methods.



## 🌟 Key Features

-   **AI Clothing Identification:** Simply upload a photo; the AI identifies the item type, color, and style.
-   **Automated Categorization:** Items are automatically sorted into folders (Tops, Bottoms, Shoes, Socks, etc.).
-   **Dynamic Outfit Matching:** Get outfit suggestions based on:
    -   **Live Weather:** Fetches your local temperature via OpenWeather API.
    -   **Manual Overwrite:** Includes an interactive temperature slider that overrides GPS data when touched.
    -   **Contextual Logic:** Adjusts for mood (Happy, Professional, etc.) and travel (Walking, Cycling, Driving).
-   **Visual Feedback Loop:** Don't like a suggestion? Chat with the AI to refine the look (e.g., "It's too cold for this" or "I want a different color").
-   **Security First:** Uses `envied` for API key obfuscation and protection.

## 🚀 Getting Started

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (Stable channel)
* [Google AI Studio API Key](https://aistudio.google.com/) (for Gemini)
* [OpenWeatherMap API Key](https://openweathermap.org/api)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/YOUR_USERNAME/smart-wardrobe-ai.git](https://github.com/YOUR_USERNAME/smart-wardrobe-ai.git)
    cd smart-wardrobe-ai
    ```

2.  **Configure Environment Variables:**
    Create a `.env` file in the root directory:
    ```env
    GEMINI_KEY=your_gemini_api_key_here
    WEATHER_KEY=your_openweather_api_key_here
    ```

3.  **Generate Obfuscated Keys:**
    This project uses `envied` to protect your keys. Run the generator:
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

4.  **Run the App:**
    ```bash
    flutter run
    ```

## 🛠️ Build for Windows

To generate a standalone Windows executable with code obfuscation:

```bash
flutter build windows --release --obfuscate --split-debug-info=./debug_info
