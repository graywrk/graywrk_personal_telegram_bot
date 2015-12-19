require 'telegram/bot'
require 'telegram/bot/botan'
require 'active_support'
require 'active_support/all'
require 'geocoder'
require 'open-uri'
require 'nokogiri'
require 'oj'
require 'net/http'
require 'openssl'
require 'json'

TELEGRAM_TOKEN = '135773758:AAGPnmkcWnYKg3If9uC3Pe332ZLG6q1WLls'
BOTAN_TOKEN = '4wPnoJT9Ei7vSOFSvrpES482w:NX27MP'

HELP_TEXT = <<END
/start - Старт приложения
/time - Текущее время
/keyboard - Простая клавиатура
/picture - Показать картинку
/audio - Проиграть мелодию
/sticker - Показать стикер
/find <Место> - Найти на карте <Место>
/bash_random - Случайная цитата с bash.im
/bash_daily_best - Лучшие цитаты за день с bash.im
/weather <Город> - Погода в городе <Город>
/xkcd_last - Последний комикс с xkcd
/xkcd_random - Рандомный комикс с xkcd
/help - Помощь
END

def parse_url url
  Oj.load(open(url).read)
end

def parse_quotes url
  quotes = []
  Nokogiri::HTML(open(url)).css("div[class='quote']").map{ |x| 
    quotes << x.css("div[class='text']").
        children.map{|s| s.name == 'br' ? "\n" : s.text}.join
  }
  quotes.delete ""
  quotes
end

def weather(city)
  uri = URI.parse("http://api.openweathermap.org/data/2.5/weather?q="+city)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  data = JSON.parse(response.body)

  if(data["cod"] == 200)
    message = ""
    message += data["name"]+", "+data["sys"]["country"]+"\n"
    message += data["weather"][0]["main"]+": "+data["weather"][0]["description"]+"\n"
    message += (data["main"]["temp"]-272.150).signif(4).to_s+"°C"
    return message
  else
      return "Город не найден"
  end
end

class Float
  def signif(signs)
    Float("%.#{signs}g" % self)
  end
end

def xkcd(path)
  uri = URI.parse("http://xkcd.com/"+path)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  data = JSON.parse(response.body)

  return data["num"], data["img"]
end

def download(img)
  name=img.split('/').last
  Net::HTTP.start("imgs.xkcd.com") do |http|
    f = File.open(name,"wb")
    begin
        http.request_get("/comics/"+name) do |resp|
            resp.read_body do |segment|
                f.write(segment)
            end
        end
    ensure
        f.close()
    end
  end
  return name
end

Telegram::Bot::Client.run(TELEGRAM_TOKEN, logger: Logger.new($stdout)) do |bot|
  bot.logger.info('Bot has been started')
  bot.enable_botan!(BOTAN_TOKEN)
  bot.listen do |message|
    full_message, command, params = /\/(\w*)\s*(.*)/.match(message.text).to_a
    bot.logger.info("full_message: #{full_message}, command: #{command}, params: #{params}")
    case command
      when 'start'
        bot.api.sendMessage(chat_id: message.chat.id, text: "Привет #{message.from.first_name}! Если не знаешь что делать набери /help")
        # bot.track('/start', message.from.id, type_of_chat: message.chat.class.name)
      when 'time'
        bot.api.sendMessage(chat_id: message.chat.id, text: "Точное время #{Time.now}")
      when 'keyboard'
        answers = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: [%w(A B), %w(C D)], one_time_keyboard: true)
        bot.api.send_message(chat_id: message.chat.id, text: "Тестовая клавиатура", reply_markup: answers)
      when 'picture'
        bot.api.send_photo(chat_id: message.chat.id, photo: File.new('test.jpg'))
      when 'audio'
        bot.api.send_audio(chat_id: message.chat.id, audio: File.new('test.mp3'))
      when 'sticker'
        bot.api.send_sticker(chat_id: message.chat.id, sticker: File.new('test.webp'))
      when 'find'
        if !params.empty?
          locations = Geocoder.search(params)
          if locations.empty?
            bot.logger.info("Place not found")
            bot.api.send_message(chat_id: message.chat.id, text: "Ничего не нашлось :(")
          end
          locations.each do |location|
            bot.logger.info("lat: #{location.latitude}, long: #{location.longitude}")
            bot.api.send_location(chat_id: message.chat.id, latitude:  location.latitude, longitude: location.longitude)
          end
        end
      when 'bash_random'
        bash_quotes = parse_quotes("http://bash.im/random")
        reply_text = Oj.dump(bash_quotes.sample) || "Данные не получены"
        reply_text = reply_text.gsub(/\\r\\n|\\r|\\n/, "\n")
        bot.api.sendMessage(chat_id: message.chat.id, text: reply_text)
      when 'bash_daily_best'
        bash_quotes = parse_quotes("http://bash.im/best")
        reply_text = Oj.dump(bash_quotes) || "Данные не получены"
        reply_text = reply_text.gsub(/\\r\\n|\\r|\\n/, "\n")
        bot.api.sendMessage(chat_id: message.chat.id, text: reply_text)   
      when 'weather'
        bot.api.sendMessage(chat_id: message.chat.id, text: weather(URI::encode(params)))
      when 'xkcd_last'
        num,img = xkcd("info.0.json")
        path=download(img)
        if File.exist?(path)
          File.open(path){ |f|
            bot.api.send_photo(chat_id: message.chat.id, photo: f)
          }
          File.delete(path)
        else
          puts "Error:".red+" File not exist #{path}"
        end
      when 'xkcd_random'
        num,img = xkcd("info.0.json")
        num,img = xkcd((1 + Random.rand(num)).to_s+"/info.0.json")
        path=download(img)
        if File.exist?(path)
          File.open(path){ |f|
            bot.api.send_photo(chat_id: message.chat.id, photo: f)
          }
          File.delete(path)
        else
          puts "Error:".red+" File not exist #{path}"
        end
      when 'help'
        bot.api.sendMessage(chat_id: message.chat.id, text: HELP_TEXT)
      else
        bot.api.sendMessage(chat_id: message.chat.id, text: "Не знаю такой команды. Набери /help")
    end
  end
end