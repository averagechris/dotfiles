var ENV = "eventbrite";
var PATTERN = /\b[0-9]{11}\b/g;
var INPUT = `%clipboard`;
var ID = INPUT.match(PATTERN);

if (!ID) {
	// handle the ID not matching the needed pattern
	var app = Application.currentApplication();
	var message = "Please copy valid input";

   	app.includeStandardAdditions = true;
	app.displayNotification(message, {
		withTitle: "Lookup Something",
		subtitle: "Not valid input",
		soundName: "text"
	});
} else {
	ID = ID[0];
	var URL = "https://" + ENV + "" + ID + "";
	var chrome = Application('Google Chrome');
	var tab = chrome.Tab({url: URL});

	chrome.windows[0].tabs.push(tab);
	chrome.activate();
}
