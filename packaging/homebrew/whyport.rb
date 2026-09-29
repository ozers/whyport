cask "whyport" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/__REPOSITORY__/releases/download/v#{version}/WhyPort.dmg"
  name "WhyPort"
  desc "Menu bar app that shows why a port is open, who uses it, and stops it"
  homepage "https://github.com/__REPOSITORY__"

  depends_on macos: ">= :sonoma"

  app "WhyPort.app"

  zap trash: [
    "~/Library/Logs/WhyPort",
    "~/Library/Preferences/dev.whyport.app.plist",
  ]
end
