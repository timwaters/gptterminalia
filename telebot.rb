require 'dotenv/load'
require 'telegram/bot'
require "openai"
require "down"
require "base64"
require 'yaml/store'

token = ENV["TELEGRAM_TOKEN"]
openai_token = ENV["OPENAI_TOKEN"]
default_prompt = ENV["DEFAULT_PROMPT"]
admin_id = ENV["ADMIN_ID"]

openai_client = OpenAI::Client.new(access_token: openai_token)

store = YAML::Store.new "prompt.store"

store.transaction do
  if store["prompt"].nil?
    store["prompt"] = [default_prompt]
  end
end

Telegram::Bot::Client.run(token) do |bot|

  bot.listen do |message|
    if message.text
      case message.text
        when '/start'
          bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
        when '/stop'
          bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name}")
        when '/help'
          bot.api.send_message(chat_id: message.chat.id, text: "Help text here")
        when '/chat'
          response = openai_client.chat(
            parameters: {
                model: "gpt-3.5-turbo", # Required.
                messages: [{ role: "user", content: "Hello!"}], # Required.
                temperature: 0.7,
            })
          chatmsg = response.dig("choices", 0, "message", "content")
          bot.api.send_message(chat_id: message.chat.id, text: chatmsg)
        when '/prompts'
          if message.from.id == admin_id.to_i
            store.transaction(true) do
              prompts = store["prompt"]
              allprompts = prompts.join("\n\n")
              if allprompts.length > 4000
                (0...allprompts.length).step(4000) do | n |
                  bot.api.send_message(chat_id: message.chat.id, text: allprompts[n..n+4000])
                end
              else
                bot.api.send_message(chat_id: message.chat.id, text: allprompts)
              end
            end
          end
        when /^\/setprompt/
          if message.from.id == admin_id.to_i
            message.text.slice!("/setprompt ")
            store.transaction do
              store["prompt"] << message.text
            end
            bot.api.send_message(chat_id: message.chat.id, text: "stored new prompt, use /prompts to list all prompts")
          end
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Sorry, I can't interact in this way. Try /help or send me a photo. ")

      end #case


    elsif message.photo
        prompt = default_prompt
        store.transaction(true) do
          prompt = store["prompt"][-1] 
        end
        
        file = bot.api.get_file(file_id: message.photo[-1].file_id)
        file_path = file.file_path
        url = "https://api.telegram.org/file/bot#{ENV['TELEGRAM_TOKEN']}/#{file_path}"
        tempfile = Down.download(url)

        msg = bot.api.send_message(chat_id: message.chat.id, text: "Sending image to the AI now, this might take a minute...")
        
        bot.api.send_chat_action(chat_id: message.chat.id, action: "upload_photo")

        base64_image = Base64.strict_encode64(tempfile.read)

        oa_messages = [
          { "type": "text", "text": prompt},
          { "type": "image_url",
            "image_url": {
              "url":  "data:image/jpeg;base64,#{base64_image}",
              "quality": "high"
            },
          }
        ]
        response = openai_client.chat(
            parameters: {
                model: "gpt-4-vision-preview", # Required.
                messages: [{ role: "user", content: oa_messages}], # Required.
                max_tokens: 2000,
            })
        puts response.inspect
        chatmsg = response.dig("choices", 0, "message", "content")

        bot.api.edit_message_text(chat_id: message.chat.id, message_id: msg.message_id, text: chatmsg)
       # bot.api.send_message(chat_id: message.chat.id, text: chatmsg)

        tempfile.unlink  #delete temp file
        encoded = nil  #just in case!
    else #phot

      bot.api.send_message(chat_id: message.chat.id, text: "Sorry, this bot didnt understand that. Try /help ")
    end

  end
end