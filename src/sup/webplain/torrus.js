/**
 * Parameter definitions - list of parameters the server supports.
 */
var torrusParams = [
    // { name:     "Gstart",
    //   type:     "number",
    //   desc:     "Starting hour",
    //   args:     [ ["min", 0], ["max", 22] ],
    // },
    // { name:     "Gend",
    //   type:     "number",
    //   desc:     "Ending hour",
    //   args:     [ ["min", 1], ["max", 23] ],
    // },
    { name:     "Gmaxline",
      type:     "checkbox",
      desc:     "Draw maximum value",
      args:     [ ],
    },
    { name:     "Gmaxlinestep",
      type:     "number",
      desc:     "Aggregation period (secs)",
      args:     [ ["min", 1] ],
    },
];

/**
 * Graph controls scriptlet - code executed per graph on the page.
 * @param index     Number of graph (starting from 0).
 * @param object    The DOM element of the surrounding DIV tag.
 */
function graphControls(index, object) {
    var div = $(object);
    var graph = div.children("img");
    var controls = div.children("div.GraphControls");

    // Initialize controls box.
    // We place the controls box on the right side of every graph.
    controls.hide();
    var width = graph.width();
    var height = graph.height();
    controls.css("height", (height - 2) + "px");
    controls.css("margin-top", (-height) + "px");
    controls.css("margin-left", (width + 10) + "px");

    // Add hover callback on surrounding DIV.
    div.hover(
        function() { controls.fadeIn(); },
        function() { controls.fadeOut(); }
    );

    // Add controls to the control box.
    controls.html("<br/>");

    for(i in torrusParams) {
        param = torrusParams[i];
        controls.append("<strong>" + param.desc + "</strong><br/>");

        // Create input field
        var input = $("<input></input>");
        input.attr("name", param.name);
        input.attr("type", param.type);
        for(j in param.args) {
            arg = param.args[j];
            input.attr(arg[0], arg[1]);
        }
        controls.append(input);

        // Set callback for updating image 
        input.change(function() {
            var value, field = $(this);

            if(field.attr("type") == "checkbox") {
                value = field.filter(":checked").length;
            } else {
                value = field.val();
            }
            
            graph.attr("src", 
                $.param.querystring(
                    graph.attr("src"),
                    field.attr("name") + '=' + value)); 
        });

        controls.append("<br/><br/>");
    }
}

/**
 * Window load callback - called as soon as the document has been loaded
 * into the browser and we can start running the script.
 */
$(window).load(function() {
    $.each($("div.GraphImage"), graphControls);
})
