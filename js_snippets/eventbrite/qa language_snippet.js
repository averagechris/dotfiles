var ENV = "evbqa";
var PATTERN = /\b[0-9]{11}\b/g;
var app = Application.currentApplication();
app.includeStandardAdditions();
var INPUT = app.theClipboard();
var ID = INPUT.match(PATTERN);

if (!ID) {
	var message = "Please copy an event ID and try again.";

	app.displayNotification(message, {
		withTitle: "Language Settings Lookup",
		subtitle: "Not an Event ID",
		soundName: "text"
	});
} else {
	ID = ID[0];
	var URL = "https://" + ENV + ".com/language?eid=" + ID;
	var chrome = Application('Google Chrome');
	var tab = chrome.Tab({url: URL});

	chrome.windows[0].tabs.push(tab);
	chrome.activate();
}
ignoreOutput;
