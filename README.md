# PC Remote

Shut down, lock, restart and watch your Windows PC from your phone. Every action needs your **fingerprint**, and it works from anywhere, not just your home Wi-Fi. Free.

### [⬇ Download PC-Remote.zip](https://github.com/PAAOPAO17/SHUTUP/raw/main/PC-Remote.zip)

## Install in 3 steps

1. **Download and extract.** Click the download link above, then right-click the zip and choose **Extract All**.
2. **Double-click `START HERE.bat`** and click **Yes**.
   - If Windows SmartScreen warns you, click **More info**, then **Run anyway**.
   - It installs **Docker Desktop** and **Tailscale** for you if you don't have them, signs you in and sets everything up. The first time takes about 10 minutes.
   - It may ask you to restart once. It carries on by itself afterwards.
   - It may open a Tailscale page and ask you to click **Enable HTTPS**. That's a one-time click for your account.
3. **Follow the setup page.** It opens on your PC when Setup finishes and shows your link, a QR code and your setup PIN. The three steps on it tick off by themselves as you go.

**You need:** Windows 10 or 11, an internet connection, a phone with fingerprint or face unlock, and a free [Tailscale](https://tailscale.com) account (sign in with Google, Microsoft, Apple or GitHub).

## Where do I find my link?

Your link is private to your PC. It looks like `https://your-pc-name.tailXXXX.ts.net`, and only phones signed in to your Tailscale account can open it. You can find it:

- on the **setup page** that opens at the end of Setup
- from the **PC Remote setup** shortcut on your desktop
- by opening `http://localhost:8765/setup` on your PC

Once you've installed the app on your phone you won't need the link again.

## On your phone

1. Install **Tailscale** and sign in with the same account as your PC. Leave it on.
2. Open your link (scan the QR code on the setup page). Hold the power button, type the setup PIN once and register your fingerprint.
3. Tap **Install app** (iPhone: Share → **Add to Home Screen**), then **Notify me**.

## What the buttons do

| Button | What it does |
|---|---|
| Hold the power button | Shuts down the PC after your fingerprint |
| View screen | Live view of your PC screen. Pick **Data saver** on mobile data |
| Send message | Shows your text on the PC screen. Only your phone can remove it |
| Lock PC / Restart PC | Locks or restarts the PC after your fingerprint |
| Activity alerts | Notifies you when the PC is used again after sitting idle |
| Idle alert time | How long the PC must be idle first: 1 to 30 minutes |
| Notify me | Turns on notifications, including "your PC is on" |
| Add fingerprint | Registers another phone |

## If something goes wrong

| You see | Try this |
|---|---|
| **PC offline** | Make sure Tailscale is on, on your phone, and the PC is signed in to Windows. Docker and the helper only start after you sign in. |
| **PC helper not running** | Wait a minute. If it stays, double-click `START HERE.bat` again. |
| A black or frozen live view | The PC may be locked. Unlock it and try again. |
| Anything else | Double-click `START HERE.bat` again. It's safe to run as many times as you like. |

## Update or remove

- **Update:** download the newest zip and double-click `START HERE.bat` again. Your PIN and registered phones are kept.
- **Remove:** double-click `Uninstall.bat`. Docker and Tailscale stay installed.

## How it works and what it protects

- Your phone talks to your PC through **Tailscale**, a private encrypted network. Nothing is opened to the public internet.
- Every action goes through your phone's own **fingerprint check** (WebAuthn). Your fingerprint never leaves your phone.
- A small website runs in **Docker** on your PC. A hidden **helper** script carries out the actions and shares the screen. The two talk through a shared folder, `C:\pc-remote-trigger`.
- Notifications are sent through Google's or Apple's push service. Nothing about you is stored in this repo.
- Anyone who can use your PC in person can still end the helper in Task Manager. This protects against remote access, not against someone sitting at your desk.

## What's in the zip

| File | Purpose |
|---|---|
| `START HERE.bat`, `setup.ps1` | The installer |
| `Uninstall.bat`, `uninstall.ps1` | Removes everything |
| `files/` | The app: `server.py`, `index.html`, `setup.html`, `watcher.ps1`, `Dockerfile`, `docker-compose.yml` and the icons |
