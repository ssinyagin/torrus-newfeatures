/**
 * Graph controls scriptlet - code executed per graph page.
 */
function graphControls() {
    // Initialize event handlers on menu
    var controls = $('div.GraphControls');
    var options = $('ul.OptionsMenu');

    controls.hover(
        function() { options.show(100); },
        function() { options.hide(100); });

    controls.show();

    // Initialize event handlers on links
    var links = $('ul.OptionsMenu li ul li a');
        
    links.each(function() {
        $(this).click(function(event) {
            updateGraphs(event.target.href);
        });
    });
}

/**
 * Function to update the given graphs.
 */
function updateGraphs(hash) {
    var params = hash.split('#')[1];
    var graphs = $('div.GraphImage img');

    graphs.each(function() {
        var graph = $(this);
        graph.attr('src',
            $.param.querystring(
                graph.attr('src'),
                params));
    });
}

/**
 * Window load callback - called as soon as the document has been loaded
 * into the browser and we can start running the script.
 */
$(window).load(function() {
    var graphs = $('div.GraphImage');

    if(graphs.length > 0) {
        graphControls();
    }

    updateGraphs(window.location.hash);
})
