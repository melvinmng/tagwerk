// Safari preprocessing script of the share extension (NSExtensionJavaScriptPreprocessingFile).
// Safari runs it in the page before the extension opens and hands the result over as a property list. It reads the address,
// the title and the selected text of the page; nothing else of the page leaves it.
var ShareExtension = function() {};

ShareExtension.prototype = {
    run: function(parameters) {
        parameters.completionFunction({
            "url": document.URL,
            "title": document.title,
            "selection": String(window.getSelection())
        });
    },
    finalize: function(parameters) {}
};

// The name Safari looks for.
var ExtensionPreprocessingJS = new ShareExtension;
