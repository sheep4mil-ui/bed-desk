# Bed Desk

Use your phone as a wireless trackpad and keyboard for this Windows PC.

The controller includes a live view of the PC's primary screen. Tap **Screen
on** in the phone header to pause the screen feed and reduce data use; tap it
again to resume.

## Start

1. Put the PC and phone on the same Wi-Fi.
2. Double-click **Start Bed Desk.bat**.
3. Approve the Windows administrator prompt.
4. Open the address shown in the black window on your phone.
5. Enter the six-digit PIN.

Keep the black window open while using the controller. Press `Ctrl+C` in that
window, close it, or tap **Stop PC control** on the phone to stop.

The controller is local-only: it does not use an account or send commands
through the internet. A new PIN is generated every time it starts.

## Use it over cellular

1. Double-click **Start Bed Desk - Cellular.bat**.
2. On the first run, wait while the secure tunnel helper downloads.
3. Open the permanent Bed Desk GitHub website on your phone.
4. Enter the eight-character code shown on the PC.

The launcher opens a small setup tab on the PC; keep that tab and the launcher
window open. Cellular mode works from any internet connection. Its pairing code,
private tunnel address, and PIN are regenerated each time. Do not share the
pairing code. Closing the PC window immediately stops the controller and tunnel.

The same controller page is also included as `index.html` for GitHub Pages.

## If the phone cannot connect

- Confirm both devices are on the same Wi-Fi and cellular data/VPN is off.
- Allow PowerShell on **Private networks** if Windows Firewall asks.
- Make sure the Wi-Fi is marked **Private** in Windows Settings.
- Guest Wi-Fi often blocks devices from talking to each other.
