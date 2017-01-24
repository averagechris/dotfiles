var ENV = "eventbrite";
var PATTERN = /\b[0-9]{11}\b/g;
var INPUT = `%clipboard`;
var ID = INPUT.match(PATTERN);

if (!ID) {
	var app = Application.currentApplication();
	var message = "Please copy an event ID and try again.";

   	app.includeStandardAdditions = true;
	app.displayNotification(message, {
		withTitle: "Waitlist Settings Lookup",
		subtitle: "Not an Event ID",
		soundName: "text"
	});
} else {
	ID = ID[0];
	var URL = "https://" + ENV + ".com/waitlist-settings?eid=" + ID;
	var chrome = Application('Google Chrome');
	var tab = chrome.Tab({url: URL});

	chrome.windows[0].tabs.push(tab);
	chrome.activate();
}
