# PC Remote

Shut down, lock, restart and watch your **Windows PC or Mac** from your **iPhone or Android phone**. Every action needs your **fingerprint** or face unlock, and it works from anywhere, not just your home Wi-Fi. Free.

### [⬇ Download PC-Remote.zip](https://github.com/PAAOPAO17/SHUTUP/raw/main/PC-Remote.zip)

| Your computer | Your phone | Works? |
|---|---|---|
| Windows 10 / 11 | iPhone, iPad or Android | ✅ |
| Mac (macOS 12 or newer) | iPhone, iPad or Android | ✅ New, see the [Mac notes](#mac-notes) |

## Install on Windows

1. **Download and extract.** Click the download link above, then right-click the zip and choose **Extract All**.
2. **Double-click `START HERE.bat`** and click **Yes**. If SmartScreen warns you, click **More info**, then **Run anyway**.
   - It installs **Docker Desktop** and **Tailscale** for you if you don't have them, signs you in and sets everything up. The first time takes about 10 minutes.
   - It may ask you to restart once. It carries on by itself afterwards.
3. **Follow the setup page** that opens on your PC (see [below](#the-setup-page)).

## Install on Mac

1. **Download and extract.** Double-click the zip.
2. **Right-click `START HERE (Mac).command`**, choose **Open**, then **Open** again. If Terminal says "permission denied", run `bash "START HERE (Mac).command"` in Terminal instead.
3. **Follow the messages in the window.** It sets up Docker Desktop and Tailscale (it installs them if you use Homebrew, otherwise it opens their download pages and waits for you).
4. **Allow the permissions.** macOS asks about "PC Remote Helper". Click **Allow**, and in **System Settings → Privacy & Security → Screen Recording** turn on **PC Remote Helper**. That's needed for View screen.
5. **Follow the setup page** that opens (see below).

## The setup page

When Setup finishes, a page opens on your computer with everything you need: your link, a QR code and your setup PIN. It has three steps that **tick off by themselves**:

1. **Put Tailscale on your phone** and sign in with the same account (it shows which one).
2. **Open your link** (scan the QR code), type the setup PIN once and register your fingerprint.
3. **Install the app** (Android: **Install app**; iPhone: Share → **Add to Home Screen**) and tap **Notify me**.

**You need:** an internet connection, a phone with fingerprint or face unlock, and a free [Tailscale](https://tailscale.com) account (sign in with Google, Microsoft, Apple or GitHub). The first time, Tailscale may ask you to click **Enable HTTPS** on a web page. That's a one-time click.

## Where do I find my link?

It looks like `https://your-computer.tailXXXX.ts.net` and only phones signed in to your Tailscale account can open it. You can find it:

- on the **setup page** that opens at the end of Setup
- from the **PC Remote setup** shortcut on your desktop
- by opening `http://localhost:8765/setup` on the computer itself

Once the app is installed on your phone you won't need the link again.

## What the buttons do

| Button | What it does |
|---|---|
| Hold the power button | Shuts down the computer after your fingerprint |
| View screen | Live view of the screen. Pick **Data saver** on mobile data |
| Send message | Shows your text on the screen. Only your phone can remove it |
| Lock PC / Restart PC | Locks or restarts the computer after your fingerprint |
| Activity alerts | Notifies you when the computer is used again after sitting idle |
| Idle alert time | How long it must be idle first: 1 to 30 minutes |
| Notify me | Turns on notifications, including "your computer is on" |
| Add fingerprint | Registers another phone |

## Mac notes

- **Lock:** it uses your Mac's own lock. Set **System Settings → Lock Screen → Require password after screen saver begins or display is turned off** to **Immediately**.
- **Shut down and Restart** ask macOS the way the Apple menu does, so a program with unsaved work can stop it. On Windows they are forced.
- **View screen shows only the wallpaper?** Screen Recording isn't allowed yet. Turn on **PC Remote Helper** under Privacy & Security → Screen Recording, then open `START HERE (Mac).command` again to restart the helper.
- **Live view is a little slower on a Mac** (a few frames per second), because macOS takes screenshots one at a time.
- Messages appear as plain text over everything, including full-screen apps, and clicks pass through them.

## If something goes wrong

| You see | Try this |
|---|---|
| **PC offline** | Make sure Tailscale is on, on your phone, and the computer is logged in. Docker and the helper only start after you log in. |
| **PC helper not running** | Wait a minute. If it stays, open `START HERE` again. |
| A black or frozen live view | The computer may be locked. Unlock it and try again. |
| Anything else | Open `START HERE` again. It's safe to run as many times as you like. |

## Update or remove

- **Update:** download the newest zip and open `START HERE` again. Your PIN and registered phones are kept.
- **Remove:** `Uninstall.bat` on Windows, `Uninstall (Mac).command` on Mac. Docker and Tailscale stay installed.

## How it works and what it protects

- Your phone talks to your computer through **Tailscale**, a private encrypted network. Nothing is opened to the public internet.
- Every action goes through your phone's own **fingerprint check** (WebAuthn). Your fingerprint never leaves your phone.
- A small website runs in **Docker** on your computer. A **helper** carries out the actions and shares the screen: a hidden PowerShell script on Windows, a shell script in a small background app on Mac. The two talk through a shared folder.
- Notifications are sent through Google's or Apple's push service. Nothing about you is stored in this repo.
- Anyone who can use your computer in person can still stop the helper. This protects against remote access, not against someone sitting at your desk.

## What's in the zip

| File | Purpose |
|---|---|
| `START HERE.bat`, `setup.ps1` | Windows installer |
| `START HERE (Mac).command`, `setup-mac.sh` | Mac installer |
| `Uninstall.bat` / `Uninstall (Mac).command` | Remove everything |
| `files/` | The app: `server.py`, `index.html`, `setup.html`, `watcher.ps1` (Windows helper), `Dockerfile`, `docker-compose.yml` and the icons |
| `mac/` | The Mac helper (`helper.sh`, `overlay.js`) and its `docker-compose.yml` |
