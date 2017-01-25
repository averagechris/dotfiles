var chrome = Application("Google Chrome"); chrome.includeStandardAdditions = true;
var INPUT =  "\"".concat(chrome.theClipboard()).concat("\"");
var URL = "https://github.com/eventbrite/core/search?utf8=✓&q=" + encodeURIComponent(INPUT);
var chrome = Application("Google Chrome");var tab = chrome.Tab({url: URL});
chrome.windows[0].tabs.push(tab);
chrome.activate();
ignoreOutput;
