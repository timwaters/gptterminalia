require 'dotenv/load'
require 'telegram/bot'
require "openai"
require "down"
require "base64"

token = ENV["TELEGRAM_TOKEN"]
openai_token = ENV["OPENAI_TOKEN"]

openai_client = OpenAI::Client.new(access_token: openai_token)

Telegram::Bot::Client.run(token) do |bot|

  bot.listen do |message|
  
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
    when '/stop'
      bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name}")
    when '/chat'
      
      response = openai_client.chat(
        parameters: {
            model: "gpt-3.5-turbo", # Required.
            messages: [{ role: "user", content: "Hello!"}], # Required.
            temperature: 0.7,
        })
      puts response.dig("choices", 0, "message", "content")
      chatmsg = response.dig("choices", 0, "message", "content")

      bot.api.send_message(chat_id: message.chat.id, text: chatmsg)

    end

    if message.photo

      file = bot.api.get_file(file_id: message.photo[-1].file_id)
      file_path = file.file_path
      url = "https://api.telegram.org/file/bot#{ENV['TELEGRAM_TOKEN']}/#{file_path}"
      tempfile = Down.download(url)

      base64_image = Base64.strict_encode64(tempfile.read)

      bot.api.send_message(chat_id: message.chat.id, text: "Got image, sending it to the AI now...")

      oa_messages = [
        { "type": "text", "text": "What's in this image?"},
        { "type": "image_url",
          "image_url": {
            "url":  "data:image/jpeg;base64,#{base64_image}"
          },
        }
      ]
      response = openai_client.chat(
          parameters: {
              model: "gpt-4-vision-preview", # Required.
              messages: [{ role: "user", content: oa_messages}], # Required.
              max_tokens: 300,
          })
      puts response.inspect
      chatmsg = response.dig("choices", 0, "message", "content")

      
      bot.api.send_message(chat_id: message.chat.id, text: chatmsg)

      tempfile.unlink  #delete temp file
      encoded = nil
      
    end
  end
end