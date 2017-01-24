var ENV = "eventbrite";
var INPUT = `%clipboard`;
var PATTERN = /\b[0-9]{11}\b/g;

ID = INPUT.match(PATTERN);

if (!ID) {
	var app = Application.currentApplication();
	var message = "Please copy an event ID and try again.";

	app.includeStandardAdditions = true;
	app.displayNotification(message, {
		withTitle: "Event Lookup",
		subtitle: "Not an Event ID",
		soundName: "text"
	});
} else {
	var URL = "https://www." + ENV + ".com/edit?eid=" + ID;
	var chrome = Application('Google Chrome');
	var tab = chrome.Tab({url: URL});

	chrome.windows[0].tabs.push(tab);
	chrome.activate();
}
ignoreOutput;
