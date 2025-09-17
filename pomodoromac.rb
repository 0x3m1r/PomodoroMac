class Pomodoromac < Formula
  desc "Basic pomodoro for macOS"
  homepage "https://github.com/0x3m1r/PomodoroMac"
  url "https://github.com/0x3m1r/PomodoroMac/pomodoro_for_mac.tar.gz"
  sha256 "c07c2c84acaa752e36e180e6534f2cd9cfb30bd6298009ef6156a04adc19845b"
  version "0.1"


  def install
    prefix.install "pomodoro_for_mac.app"
    bin.write_exec_script "#{prefix}/pomodoro_for_mac.app/Contents/MacOS/pomodoro_for_mac"
  end
end