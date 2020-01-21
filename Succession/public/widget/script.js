(function() {

// Localize jQuery variable
var jQuery;

var mustache_tag = document.createElement('script');
mustache_tag.setAttribute("type","text/javascript");
mustache_tag.setAttribute("src",
  "https://cdnjs.cloudflare.com/ajax/libs/mustache.js/3.1.0/mustache.min.js");
(document.getElementsByTagName("head")[0] || document.documentElement).appendChild(mustache_tag);

/******** Load jQuery if not present *********/
if (window.jQuery === undefined || window.jQuery.fn.jquery !== '3.4.1') {
    var script_tag = document.createElement('script');
    script_tag.setAttribute("type","text/javascript");
    script_tag.setAttribute("src",
        "https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js");
    if (script_tag.readyState) {
      script_tag.onreadystatechange = function () { // For old versions of IE
          if (this.readyState == 'complete' || this.readyState == 'loaded') {
              scriptLoadHandler();
          }
      };
    } else { // Other browsers
      script_tag.onload = scriptLoadHandler;
    }
    // Try to find the head, otherwise default to the documentElement
    (document.getElementsByTagName("head")[0] || document.documentElement).appendChild(script_tag);
} else {
    // The jQuery version on the window is the one we want to use
    jQuery = window.jQuery;
    main();
}

/******** Called once jQuery has loaded ******/
function scriptLoadHandler() {
    // Restore $ and window.jQuery to their previous values and store the
    // new jQuery in our local jQuery variable
    jQuery = window.jQuery.noConflict(true);
    // Call our main function
    main();
}

/******** Our main function ********/
function main() {
    jQuery(document).ready(function($) {
        // We can use jQuery here
        var data_url = "https://lineofsuccession.co.uk/api?callback=?";
        $.getJSON(data_url, function(json) {
          var succ = $('div');
          succ.append = $('<h1>Line of Succession on ' + json.date + '</h1>');
          alert(json.sovereign.name);
          $('#line-of-succession-widget-container').append(succ);
        });
    });
}

})();

