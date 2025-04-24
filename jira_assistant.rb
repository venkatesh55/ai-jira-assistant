require 'net/http'
require 'uri'
require 'json'
require 'date'
require 'dotenv'
require 'io/console'
require 'securerandom'

# Load environment variables from .env file
Dotenv.load

class JiraAssistant
  OPENAI_API_KEY = ENV['OPENAI_API_KEY']
  JIRA_API_TOKEN = ENV['JIRA_API_TOKEN']
  JIRA_USERNAME = ENV['JIRA_USERNAME']
  JIRA_BASE_URL = ENV['JIRA_BASE_URL']
  MAX_RECORDING_SECONDS = 20

  def initialize
    validate_env_variables
  end

  def run
    display_welcome_message
    
    loop do
      print "> "
      
      # Check if first character is 'v' for voice input
      first_char = STDIN.getch
      if first_char.downcase == 'v'
        puts "v (Voice mode)"
        input = get_voice_input
        puts "Voice input: \"#{input}\""
      elsif first_char.downcase == 'e' && STDIN.getch.downcase == 'x' && STDIN.getch.downcase == 'i' && STDIN.getch.downcase == 't'
        break
      else
        # For normal text input, use the first character and then get the rest
        print first_char
        input = first_char + gets.to_s.chomp
      end
      
      # Check again for exit after getting full input
      break if input.downcase == 'exit'
      
      process_input(input)
    end
  end

  private

  def display_welcome_message
    puts "Welcome to JIRA Work Logger!"
    puts "Enter your work details in natural language (e.g., 'I spent 2 hours on PROJ-123 fixing bugs'):"
    puts "Press 'v' to use voice input, or just start typing for text input"
    puts "Type 'exit' to quit"
  end
  
  def process_audio_file(audio_file)
    puts "Processing speech to text from file: #{audio_file}"
    
    # Try OpenAI Whisper API for transcription
    if OPENAI_API_KEY
      puts "Transcribing audio with OpenAI Whisper..."
      whisper_text = openai_whisper_transcription(audio_file)
      
      if whisper_text && !whisper_text.empty?
        # Check if the transcription has meaningful content (not just punctuation)
        cleaned_text = whisper_text.gsub(/[^\w\s]/, '').strip
        if cleaned_text.empty? || cleaned_text.length < 5
          puts "Warning: Transcription returned minimal content: \"#{whisper_text}\""
          puts "Audio might be too quiet or unclear. The audio file has been preserved for reference."
          print "Would you like to manually type what was said instead? (y/n): "
          if gets.chomp.downcase == 'y'
            print "Please type what was said: "
            text = gets.chomp
            return text
          else
            return "(Insufficient speech content detected)"
          end
        end
        
        puts "Transcription complete: \"#{whisper_text}\""
        
        # Delete the temporary audio file after successful processing
        File.delete(audio_file) if File.exist?(audio_file)
        puts "Temporary audio file deleted"
        
        return whisper_text
      end
    end
    
    # If OpenAI Whisper failed, provide option for manual input
    puts "Speech recognition failed. The audio file has been preserved at: #{audio_file}"
    print "Would you like to manually type what was said instead? (y/n): "
    if gets.chomp.downcase == 'y'
      print "Please type what was said: "
      text = gets.chomp
      return text
    else
      return "(Speech recognition failed)"
    end
  end
  
  def openai_whisper_transcription(audio_file)
    begin
      # Create a multipart form request
      uri = URI.parse("https://api.openai.com/v1/audio/transcriptions")
      
      # Read file as binary
      file_content = File.binread(audio_file)
      
      boundary = "whisper-boundary-#{SecureRandom.hex}"
      post_body = []
      
      # Add the file part
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(audio_file)}\"\r\n"
      post_body << "Content-Type: audio/wav\r\n\r\n"
      post_body << file_content
      post_body << "\r\n"
      
      # Add the model part
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
      post_body << "whisper-1"
      post_body << "\r\n"
      
      # Add the language part
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"language\"\r\n\r\n"
      post_body << "en"
      post_body << "\r\n"
      
      # Close the form
      post_body << "--#{boundary}--\r\n"
      
      # Create the HTTP request
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = post_body.join
      
      # Send the request
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      if response.code.to_i == 200
        result = JSON.parse(response.body)
        return result["text"]
      else
        puts "Error calling OpenAI Whisper API: #{response.code}"
        return nil
      end
    rescue => e
      puts "Error during transcription: #{e.message}"
      return nil
    end
  end

  def get_voice_input
    begin
      puts "Recording... Speak now and press Ctrl+C when finished (max #{MAX_RECORDING_SECONDS} seconds)"
      
      # Create audio directory if it doesn't exist
      audio_dir = File.join(File.dirname(__FILE__), "audio_recordings")
      Dir.mkdir(audio_dir) unless Dir.exist?(audio_dir)
      
      # Save the audio file in the workspace directory
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      audio_file = File.join(audio_dir, "jira_voice_input_#{timestamp}.wav")
      
      # Record audio using arecord (ALSA) with output redirected to suppress the recording message
      recording_command = "arecord -d #{MAX_RECORDING_SECONDS} -f cd -r 16000 -c 1 #{audio_file} 2>/dev/null"
      
      recording_success = system(recording_command)
      
      # Check if the file was created and has actual content
      if File.exist?(audio_file) && File.size(audio_file) > 1000
        # Process the audio file
        text = process_audio_file(audio_file)
        return text
      else
        puts "No audio detected or recording too short."
        puts "If you're using headphones with microphone, try switching to your device's Digital Microphone instead."
        return "(No audio detected - please try again after checking your microphone settings)"
      end
      
    rescue Interrupt
      puts "\nRecording stopped by user."
      
      # Check if we have a valid recording despite the interruption
      if defined?(audio_file) && File.exist?(audio_file) && File.size(audio_file) > 1000
        puts "Processing audio..."
        # Process the audio file even though recording was interrupted
        text = process_audio_file(audio_file)
        return text
      else
        return "(Recording interrupted too early - please try again)"
      end
    rescue => e
      puts "Error during voice input: #{e.message}"
      return "(Error: #{e.message})"
    end
  end
  
  def test_microphone
    puts "Testing microphone... Speak for 5 seconds to check if your microphone is working."
    puts "You should see audio level indicators if your microphone is working properly."
    puts "(Press Ctrl+C to stop the test at any time)"
    
    begin
      # Run a short microphone test without saving the file
      system("timeout 5s rec -r 16000 -c 1 /dev/null trim 0 5")
      puts "Microphone test completed. Did you see audio level indicators moving? (y/n)"
      if gets.chomp.downcase != 'y'
        puts "Microphone may not be working properly. Please check your system sound settings."
        puts "Would you like to open your system sound settings? (y/n)"
        if gets.chomp.downcase == 'y'
          system("gnome-control-center sound &") if system("which gnome-control-center > /dev/null 2>&1") 
          system("pavucontrol &") if system("which pavucontrol > /dev/null 2>&1")
          puts "Please configure your microphone and press Enter when ready..."
          gets
        end
      else
        puts "Microphone appears to be working properly."
      end
    rescue Interrupt
      puts "Microphone test interrupted."
    end
  end

  def validate_env_variables
    missing_vars = []
    missing_vars << "OPENAI_API_KEY" unless OPENAI_API_KEY
    missing_vars << "JIRA_API_TOKEN" unless JIRA_API_TOKEN
    missing_vars << "JIRA_USERNAME" unless JIRA_USERNAME
    missing_vars << "JIRA_BASE_URL" unless JIRA_BASE_URL
    
    unless missing_vars.empty?
      puts "Error: Missing environment variables: #{missing_vars.join(', ')}"
      puts "Please create a .env file with these variables."
      exit 1
    end
  end

  def process_input(input)
    puts "Processing your input..."
    
    # Get JSON structure from OpenAI
    work_logs = extract_work_logs(input)
    
    if work_logs.empty?
      puts "No JIRA tickets identified in your input."
      display_welcome_message  # Show welcome message again
      return
    end
    
    # Log work to JIRA for each ticket
    work_logs.each do |log|
      ticket_id = log[:ticket_id]
      time_spent = log[:time_spent]
      comment = log[:comment]
      work_date = log[:work_date]
      
      puts "Logging #{time_spent} to #{ticket_id} on #{work_date}..."
      result = log_work_to_jira(ticket_id, time_spent, comment, work_date)
      
      if result[:success]
        puts "✅ Successfully logged work to #{ticket_id}"
      else
        puts "❌ Failed to log work to #{ticket_id}: #{result[:error]}"
      end
    end
    
    # Display welcome message again for a fresh start
    puts "\n"
    display_welcome_message
  end

  def extract_work_logs(input)
    today = Date.today.iso8601
    yesterday = (Date.today - 1).iso8601
    day_before_yesterday = (Date.today - 2).iso8601
    
    system_prompt = <<~PROMPT
      You are a JIRA work log assistant. Your task is to extract JIRA ticket numbers and time spent from 
      natural language input. The input may contain multiple tickets.
      
      Today's date is #{today}. When the input contains relative dates like "yesterday", "last Friday", etc.,
      convert them to the appropriate ISO date format.
      
      Extract the following information:
      1. JIRA ticket IDs (usually in format like PROJECT-123)
      2. Time spent on each ticket (convert to Jira format: 1h 30m, 45m, etc.)
      3. Work description for each ticket
      4. The date when the work was done (defaults to today if not specified)
         - For "yesterday", use #{yesterday}
         - For "day before yesterday", use #{day_before_yesterday}
         - For other relative dates, calculate the appropriate date relative to today (#{today})
      
      Return a JSON object with an "entries" array where each item has the following structure:
      {
        "entries": [
          {
            "ticket_id": "PROJECT-123",
            "time_spent": "1h 30m",
            "comment": "Brief description of work done",
            "work_date": "2025-04-23"
          },
          {
            "ticket_id": "PROJECT-456",
            "time_spent": "2h",
            "comment": "Another task",
            "work_date": "2025-04-22"
          }
        ]
      }
      
      Always return an array of entries, even if there's only one ticket.
      Do not include any explanation, just return valid JSON.
    PROMPT
  
    response = openai_request(system_prompt, input)
    parse_openai_response(response)
  end

  def parse_openai_response(response)
    begin
      # Extract JSON from the response
      json_content = response
      parsed_data = JSON.parse(json_content, symbolize_names: true)
      
      # Extract entries array from the response
      entries = parsed_data[:entries] || []
      
      # Format ticket IDs properly (ensure hyphen exists between project code and number)
      formatted_entries = entries.map do |item|
        # Check if the ticket ID contains a hyphen, if not, try to insert it
        if item[:ticket_id] && !item[:ticket_id].include?('-')
          # Find where the numbers start in the ticket ID
          match = item[:ticket_id].match(/^([A-Za-z]+)(\d+)$/)
          if match
            item[:ticket_id] = "#{match[1]}-#{match[2]}"
          end
        end
        item
      end
      
      puts "Parsed entries: #{formatted_entries.inspect}"
      
      formatted_entries.map do |item|
        {
          ticket_id: item[:ticket_id],
          time_spent: item[:time_spent],
          comment: item[:comment],
          work_date: item[:work_date] || Date.today.iso8601
        }
      end
    rescue JSON::ParserError => e
      puts "Error parsing OpenAI response: #{e.message}"
      puts "Response was: #{response}"
      []
    end
  end

  def openai_request(system_prompt, user_input)
    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
    
    request.body = JSON.dump({
      "model" => "gpt-4-turbo",
      "messages" => [
        {
          "role" => "system",
          "content" => system_prompt
        },
        {
          "role" => "user",
          "content" => user_input
        }
      ],
      "temperature" => 0.1,
      "response_format" => { "type" => "json_object" }
    })
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    
    if response.code.to_i == 200
      parsed_response = JSON.parse(response.body)
      parsed_response.dig("choices", 0, "message", "content")
    else
      puts "Error calling OpenAI API: #{response.code} - #{response.body}"
      "{}"
    end
  end

  def log_work_to_jira(ticket_id, time_spent, comment, work_date)
    uri = URI.parse("#{JIRA_BASE_URL}/rest/api/2/issue/#{ticket_id}/worklog")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(JIRA_USERNAME, JIRA_API_TOKEN)
    request.content_type = "application/json"
    
    # Convert ISO date to Jira's expected format
    started = DateTime.parse(work_date).strftime('%Y-%m-%dT%H:%M:%S.%L%z')
    
    request.body = JSON.dump({
      "timeSpent" => time_spent,
      "comment" => comment,
      "started" => started
    })
    
    begin
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      if response.code.to_i.between?(200, 299)
        { success: true }
      else
        { success: false, error: "API error: #{response.code} - #{response.body}" }
      end
    rescue => e
      { success: false, error: "Connection error: #{e.message}" }
    end
  end
end

if __FILE__ == $0
  JiraAssistant.new.run
end