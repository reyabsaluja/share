# Homebrew formula for share. Install with:
#   brew install --formula ./Formula/share.rb
# or add it to your own tap. Update `tag`, `revision` and the sha256 after each release.
class Share < Formula
  desc "Share files from the terminal via AirDrop, Mail, Messages, Shortcuts, or a local link"
  homepage "https://github.com/reyabsaluja/share"
  url "https://github.com/reyabsaluja/share.git",
      tag:      "v1.0.0",
      revision: "0000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/reyabsaluja/share.git", branch: "main"

  depends_on :macos => :monterey
  depends_on xcode: ["15.3", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/share"
    man1.install "docs/man/share.1" if File.exist?("docs/man/share.1")
    generate_completions_from_executable(bin/"share", "completions")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/share --version")
    assert_match "Would zip", shell_output("#{bin}/share zip #{test_fixtures("test.pdf")} --dry-run --no-copy")
  end
end
