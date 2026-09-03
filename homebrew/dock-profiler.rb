cask "dock-profiler" do
  version "1.0.0"
  sha256 "11fe9439e97059b574c84c793311c50ca914caf8ccbe92032a66f73e871b25ed"

  url "https://github.com/estruyf/dock-profiler-macos/releases/download/v#{version}/DockProfiler-#{version}-macos-universal.zip"
  name "Dock Profiler"
  desc "Menu bar app for switching between Dock profiles, each with an optional desktop"
  homepage "https://github.com/estruyf/dock-profiler-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Dock Profiler.app"

  # It is a background app with no Dock icon, so an upgrade would otherwise
  # replace the bundle out from under a copy that is still running.
  uninstall quit: "dev.eliostruyf.DockProfiler"

  # Nothing here touches your actual Dock or Desktop settings — only what
  # Dock Profiler itself keeps: its saved profiles and its own preferences.
  zap trash: [
    "~/Library/Application Support/Dock Profiler",
    "~/Library/Preferences/dev.eliostruyf.DockProfiler.plist",
    "~/Library/Saved Application State/dev.eliostruyf.DockProfiler.savedState",
  ]
end
