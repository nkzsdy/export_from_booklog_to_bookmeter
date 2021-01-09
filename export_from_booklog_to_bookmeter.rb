require 'csv'
require 'selenium-webdriver'
require 'date'
require 'io/console'

# progress_bar
$stdout.sync = true

def progress_bar(i, max = 100)
  i = max if i > max
  rest_size = 1 + 5 + 1      # space + progress_num + %
  bar_width = 79 - rest_size # (width - 1) - rest_size = 72
  percent = i * 100.0 / max
  bar_length = i * bar_width.to_f / max
  bar_str = ('#' * bar_length).ljust(bar_width)
  progress_num = '%3.1f' % percent
  print "\r#{bar_str} #{'%5s' % progress_num}%"
end

errors = []

# 読書メーターのid, pwを入力
puts '読書メーターのログイン情報を設定します'
puts 'メールアドレスを入力してください:'
bookmeter_email = gets.chomp
puts 'パスワードを入力してください:'
bookmeter_pw = STDIN.noecho(&:gets).chomp
puts 'ログインします...'

# ブラウザ処理
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--headless')
wait   = Selenium::WebDriver::Wait.new(timeout: 10)
driver = Selenium::WebDriver.for :chrome, options: options
base_url = 'https://bookmeter.com'

driver.navigate.to "#{base_url}/login"

email_input_elm = driver.find_element(:id, 'session_email_address')
email_input_elm.send_keys(bookmeter_email)

password_input_elm = driver.find_element(:id, 'session_password')
password_input_elm.send_keys(bookmeter_pw)
password_input_elm.submit

begin
  wait.until { driver.current_url == "#{base_url}/home" }
rescue => exception
  puts "ログインに失敗しました"
  exit
end

puts "ログインに成功しました"

# csvを取得
books = CSV.read('booklog_export.csv', encoding: 'Shift_JIS:UTF-8')
puts "全 #{books.size} 件の登録処理を行います"
puts '...'

books.each.with_index(1) do |book_info, idx|
  progress_bar(idx, books.size)
  # CSVの形式:
  # サービスID, アイテムID, 13桁ISBN, カテゴリ, 評価, 読書状況, レビュー, タグ, 読書メモ(非公開), 登録日時, 読了日, タイトル, 作者名, 出版社名, 発行年, ジャンル, ページ数

  book_values = {
    isbn:                 book_info[2],
    reading_state:        book_info[5],
    review:               book_info[6],
    reading_date:         book_info[10],
    title:                book_info[11],
    author_name:          book_info[12],
    publisher_name:       book_info[13],
  }

  # 読書メーターはレビューの上限文字数が255なのでそれよりも長かった場合テキストのURL生成サービス使う
  if book_values[:review].size > 255
    driver.navigate.to "http://controlc.com/"
    review_input_elm = driver.find_element(:id, 'input_text')
    review_input_elm.send_keys(book_values[:review])
    review_input_elm.submit

    review_text_url_elm = driver.find_element(:xpath, '//*[@id="wrapper"]/div[3]/div[1]/div[2]/form/input')
    wait.until { review_text_url_elm.displayed? }
    book_values[:review] = review_text_url_elm.attribute('value')
  end

  driver.navigate.to "#{base_url}/search"
  search_input_elm = driver.find_element(:xpath, '//*[@id="js_search_guidance"]/div[3]/div/input')

  search_text = 
    if book_values[:isbn].empty?
      "#{book_values[:title]} #{book_values[:author_name]} #{book_values[:publisher_name]}"
    else
      book_values[:isbn]
    end

  search_input_elm.send_keys(search_text)
  search_input_elm.submit

  wait.until { driver.find_element(:class, 'book-list__group').displayed? }

  driver.action.move_to(driver.find_element(:class, 'group__book'))
  driver.find_element(:class, 'group__book').click

  wait.until { driver.find_element(:css, 'section.modal.modal-book-registration.modal--active').displayed? }
  registration_modal_id = driver.find_element(:css, 'section.modal.modal-book-registration.modal--active').attribute('id')

  # 読書状況によってクリックする要素を分岐
  case book_values[:reading_state]
  when '読みたい'
    driver.find_element(:xpath, "//*[@id='#{registration_modal_id}']/div[1]/div[1]/div/div[2]/ul/li[4]").click
  when 'いま読んでる'
    driver.find_element(:xpath, "//*[@id='#{registration_modal_id}']/div[1]/div[1]/div/div[2]/ul/li[2]").click
  when '読み終わった'
    driver.find_element(:xpath, "//*[@id='#{registration_modal_id}']/div[1]/div[1]/div/div[2]/ul/li[1]").click

    wait.until { driver.find_element(:css, 'section.modal.modal-book-registration-read-form.modal--active').displayed? }

    if book_values[:reading_date].empty?
      driver.find_element(:name, 'read_book[read_at_unknown]').click
    else
      parsed_reading_date = Date.parse(book_values[:reading_date]).strftime('%Y/%m/%d')
      read_at_input_elm = driver.find_element(:name, 'read_book[read_at]')
      read_at_input_elm.send_keys(:control, 'a')
      read_at_input_elm.send_keys(:delete)
      read_at_input_elm.send_keys(parsed_reading_date)
    end
    review_input_elm = driver.find_element(:name, 'read_book[review]')
    review_input_elm.send_keys(book_values[:review])
    review_input_elm.submit
  when '積読'
    driver.find_element(:xpath, "//*[@id='#{registratino_modal_id}']/div[1]/div[1]/div/div[2]/ul/li[3]").click
  else
    errors << "#{idx}件目: #{book_values[:title]}/#{book_values[:author_name]} (#{book_values[:publisher_name]}) の読書状況が設定されていなかったため登録できませんでした。"
  end
end

driver.quit
puts

if errors.empty?
  puts "Completed!"
else
  errors.each{ |error| puts error }
end
