var ENV = "eventbrite";
var ID = "%clipboard";

var URL = "https://" + ENV + "" + ID + "";

var chrome = Application('Google Chrome');
var tab = chrome.Tab({url: URL});

chrome.windows[0].tabs.push(tab);
