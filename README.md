# JIRA Work Logger with Voice-to-Text

This tool helps you log work to JIRA using natural language input, either by typing or speaking.

## Setup

1. Make sure you have the required Ruby gems:

```bash
gem install dotenv
```

2. Create a `.env` file in the same directory with your credentials:

```
OPENAI_API_KEY=your_openai_api_key
JIRA_API_TOKEN=your_jira_api_token
JIRA_USERNAME=your_jira_username
JIRA_BASE_URL=https://your-jira-instance.atlassian.net
```

3. For voice-to-text functionality, install ALSA tools:

```bash
# For Ubuntu/Debian:
sudo apt-get install alsa-utils

# For Fedora/RHEL:
sudo dnf install alsa-utils

# For Arch Linux:
sudo pacman -S alsa-utils
```

## Usage

Run the script:

```bash
ruby jira_assistant.rb
```

- Type your work details (e.g., "I spent 2 hours on PROJ-123 fixing bugs")
- Or press 'v' to use voice input (speak into your microphone, then press Ctrl+C when done)
- Type 'exit' to quit

## Voice Input Examples

- "Yesterday I worked on PROJECT-123 for 3 hours implementing the login feature"
- "I spent 45 minutes on PROJECT-456 fixing bugs today"
- "Day before yesterday I worked on PROJECT-789 for 2 hours and 30 minutes on documentation"

## How Voice Input Works

1. When you press 'v', the system starts recording your voice
2. Speak clearly into your microphone
3. Press Ctrl+C when you're finished speaking
4. Your speech is sent to OpenAI's Whisper API for transcription
5. The transcribed text is then processed to extract JIRA work log details
6. Your work logs are submitted to JIRA automatically

## Troubleshooting

If you encounter issues with the voice recognition:

1. Make sure your microphone is working properly
2. **Important:** Check your system sound settings and select the correct input device
   - On many systems, "Digital Microphone" works better than "Headphones Stereo Microphone"
   - If using headphones with a built-in mic, try switching to your device's built-in microphone
   - Use `pavucontrol` or your system sound settings to change the recording device
3. Try speaking clearly and in a quiet environment
4. Check the size of the recorded audio file - if it's very small, it means no audio was recorded

## Microphone Selection Guide

If audio recording isn't working:

1. Open your system sound settings (or run `pavucontrol` from terminal)
2. Go to the "Input" or "Recording" tab
3. Select a different input device, preferably "Digital Microphone" if available
4. Try recording again with the new device selected