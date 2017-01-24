var ENV = "eventbrite";
var PATTERN = /\b[0-9]{9}\b/g;
var INPUT = `%clipboard`;
var ID = INPUT.match(PATTERN);

if (!ID) {
	var app = Application.currentApplication();
	var message = "Please copy an order ID and try again.";

   	app.includeStandardAdditions = true;
	app.displayNotification(message, {
		withTitle: "Order Lookup",
		subtitle: "Not an Order ID",
		soundName: "text"
	});
} else {
	ID = ID[0];
	var URL = "https://admin." + ENV + ".com/admin/orderinfo/?order_id=" + ID;
	var chrome = Application("Google Chrome");
	var tab = chrome.Tab({url: URL});

	chrome.windows[0].tabs.push(tab);
	chrome.activate();
}
ignoreOutput;
