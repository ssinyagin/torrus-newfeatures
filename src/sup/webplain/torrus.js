/**
 * Parameter definitions - list of parameters the server supports.
 * Callbacks are used for verifying parameters, e.g. to check that
 * Gend is at least one bigger than Gstart.
 */
var torrusParams = [
    { name:     "Gstart",
      html:     "input",
      type:     "number",
      desc:     "Starting hour",
      args:     [ ["min", 0], ["max", 22] ],
      callback: function(dom, controls) {
          var sibling = controls.find("input[name=Gend]");
          var start = parseInt($(dom).val());
          var end = parseInt($(sibling).val());
          if(end <= start || isNaN(end)) { 
            sibling.val(start + 1);
            sibling.change();
          }
      },
    },
    { name:     "Gend",
      html:     "input",
      type:     "number",
      desc:     "Ending hour",
      args:     [ ["min", 1], ["max", 23] ],
      callback: function(dom, controls) {
          var sibling = controls.find("input[name=Gstart]");
          var start = parseInt($(sibling).val());
          var end = parseInt($(dom).val());
          if(end <= start || isNaN(start)) { 
            sibling.val(end - 1);
            sibling.change();
          }
      },
    },
    { name:     "Gmaxline",
      html:     "input",
      type:     "checkbox",
      desc:     "Draw maximum value",
      args:     [ ],
      callback: function(dom, controls) {
          // No need for verification
          // Idea: If set to true, set Gmaxlinestep (if unset)?
      },
    },
    { name:     "Gmaxlinestep",
      html:     "select",
      desc:     "Aggregation period (secs)",
      args:     [ ],
      opts:     [ ["", 0], ["hourly", 3600], ["daily", 86400] ],
      callback: function(controls) {
          // No need for verification
          // Idea: If changed, set Gmaxline to true?
      },
    },
];

/**
 * Create form field.
 * @param Parameter definition (see above).
 * @return A DOM object to be appended to controls.
 */
function createField(param) {
    var field;

    if(param.html == "input") {
        field = $("<input></input>");
        field.attr("name", param.name);
        field.attr("type", param.type);

    } else if(param.html == "select") {
        field = $("<select></select>");
        field.attr("name", param.name);

        for(i in param.opts) {
            opt = param.opts[i];
            item = $("<option></option>")
            item.append(opt[0]);
            item.attr("value", opt[1]);
            field.append(item);
        }
    }

    for(j in param.args) {
        arg = param.args[j];
        field.attr(arg[0], arg[1]);
    }

    return field;
}


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
    div.css("height", height + "px");
    graph.css("width", width + "px");
    graph.css("height", height + "px");
    controls.css("max-height", height + "px");
    controls.css("top", (-height) + "px");
    controls.css("left", (width + 10) + "px");

    // Add hover callback on surrounding DIV.
    div.hover(
        function() { controls.show('slow'); },
        function() { controls.hide('slow'); }
    );

    // Add controls to the control box.
    controls.html("<br/>");

    callbacks = {}
    for(i in torrusParams) {
        param = torrusParams[i];
        controls.append("<strong>" + param.desc + "</strong><br/>");

        var field = createField(param);
        controls.append(field);
        callbacks[param.name] = param.callback;
        
        // Set callback for updating image 
        field.change(function() {
            var value, dom = $(this);
            callbacks[dom.attr("name")](dom, controls);

            if(dom.attr("type") == "checkbox") {
                // This yields 0/1 depending on checkbox state
                value = dom.filter(":checked").length;
            } else {
                value = dom.val();
            }
            
            // Update the graph
            graph.attr("src", 
                $.param.querystring(
                    graph.attr("src"),
                    dom.attr("name") + '=' + value)); 
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
    $("DIV.GraphControls select").mouseleave(function(event){
        event.stopPropagation();
    });
})
