.pragma library

// Common friendly app mappings
var KNOWN_APPS = {
  "com.google.android.youtube.tv": "YouTube",
  "com.netflix.ninja": "Netflix",
  "com.amazon.amazonvideo.livingroom": "Prime Video",
  "com.disney.disneyplus": "Disney+",
  "com.spotify.tv.android": "Spotify",
  "tv.twitch.android.app": "Twitch",
  "org.xbmc.kodi": "Kodi",
  "com.plexapp.android": "Plex",
  "com.google.android.tvlauncher": "Home Screen",
  "com.google.android.apps.tv.launcherx": "Google TV",
  "com.apple.atve.androidtv.appletv": "Apple TV"
};

function formatAppName(packageName) {
  if (!packageName) return "";
  if (KNOWN_APPS[packageName]) return KNOWN_APPS[packageName];
  
  // Try extracting meaningful name from package
  var parts = packageName.split(".");
  if (parts.length > 0) {
    var last = parts[parts.length - 1];
    return last.charAt(0).toUpperCase() + last.slice(1);
  }
  return packageName;
}

function statusDescription(state) {
  if (!state) return "";
  if (state.pairing_active) return "Waiting for PIN code...";
  if (!state.current_device) return "";
  if (!state.connected) return "Disconnected";
  if (!state.is_on) return "Standby";
  
  var app = formatAppName(state.current_app);
  if (app) {
    return app;
  }
  return "Home Screen";
}

function isDevicePaired(knownDevices, host) {
  if (!knownDevices || !Array.isArray(knownDevices)) return false;
  for (var i = 0; i < knownDevices.length; i++) {
    if (knownDevices[i].host === host && knownDevices[i].paired) {
      return true;
    }
  }
  return false;
}
