/*
	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/
	
function toggleMenu() {
	if (document.getElementById('displayFrame').style.left == '0px') {
		item1.expand()
		document.getElementById('displayFrame').style.left = '200px';
		document.getElementById('displayFrame').style.setExpression('width', 'document.body.clientWidth-200');
	} else {
		item1.collapse()
		document.getElementById('displayFrame').style.left = '0px'
		document.getElementById('displayFrame').style.setExpression('width', 'document.body.clientWidth');
	}
}

	function showCalendar(id, format) {
	  var el = document.getElementById(id);
	  if (calendar != null) {
	    // we already have some calendar created
	    calendar.hide();                 // so we hide it first.
	  } else {
	    // first-time call, create the calendar.
	    var cal = new Calendar(false, null, selected, closeHandler);
	    // uncomment the following line to hide the week numbers
	    // cal.weekNumbers = false;
	    calendar = cal;                  // remember it in the global var
	    cal.setRange(2003, 2005);        // min/max year allowed.
	    cal.create();
	  }
	  calendar.setDateFormat(format);    // set the specified date format
	  calendar.parseDate(el.value);      // try to parse the text in field
	  calendar.sel = el;                 // inform it what input field we use
	  calendar.showAtElement(el);        // show the calendar below it

	  return false;
	}

	function selected(cal, date) {
	  cal.sel.value = date; // just update the date in the input field.
	  cal.callCloseHandler();
	}
	function closeHandler(cal) {
	  cal.hide();                        // hide the calendar
	}

	function cleanUrl(fieldName) {
		var url = frames['displayFrame'].location.href;
		var args = '&' + rightString(url, '?') + '&';
		var base = leftString(url, '?');
		if (base == '') { base = url };
		var old = '&' + fieldName + '=' + middleString(args, '&'+fieldName+'=', '&');
		var tmp = leftString(args, old) + rightString(args, old);
		if (tmp != '') {
			args = tmp
		};
		if (args.length == 1) {
			args = '';
		} else {
			args = args.substring(1, (args.length-1));
		};
		return base + '?' + args;
	};

	function setDate() {
		var url = cleanUrl('NOW');
		if (url.indexOf('?') != (url.length-1)) { url = url + '&';};
		document.getElementById('NOW').value = document.getElementById('timec').options[document.getElementById('timec').selectedIndex].value +  " " + document.getElementById('dc').value;
		frames['displayFrame'].location.href = url + 'NOW=' + document.getElementById('NOW').value;
	};

	function setWindow(windowName) {
		var url = cleanUrl('WINDOW');
		if (url.indexOf('?') != (url.length-1)) { url = url + '&';};
		frames['displayFrame'].location.href = url + 'WINDOW=' + windowName;
	};

	function clearDate() {
		document.getElementById('NOW').value = '';
		frames['displayFrame'].location.href = cleanUrl('NOW');
	};

	function setShowHidden() {
		var showhidden = '';
		var url = cleanUrl('SHOWHIDDEN');
		if (url.indexOf('?') != (url.length-1)) { url = url + '&';};
		frames['displayFrame'].location.href = url + 'SHOWHIDDEN=' + (document.getElementById('showhidden').checked?1:0);
	};

	function setAutoScale() {
		var scale = '';
		var url = cleanUrl('AUTOSCALE');
		if (url.indexOf('?') != (url.length-1)) { url = url + '&';};
		frames['displayFrame'].location.href = url + 'AUTOSCALE=' + (document.getElementById('autoscale').checked?1:0);
	};

	function rightString(fullString, subString) {
	   if (fullString.indexOf(subString) == -1) {
    	  return "";
	   } else {
    	  return (fullString.substring(fullString.indexOf(subString)+subString.length, fullString.length));
	   }
	}

	function leftString(fullString, subString) {
	   if (fullString.indexOf(subString) == -1) {
    	  return "";
	   } else {
	      return (fullString.substring(0, fullString.indexOf(subString)));
	   }
	}
	function middleString(fullString, startString, endString) {
	   if (fullString.indexOf(startString) == -1) {
	      return "";
	   } else {
    	  var sub = fullString.substring(fullString.indexOf(startString)+startString.length, fullString.length);
	      if (sub.indexOf(endString) == -1) {
    	     return sub;
	      } else {
    	     return (sub.substring(0, sub.indexOf(endString)));
	      }
	   }
	}

	document.getElementById('dc').value = rightString(document.getElementById('NOW').value, ' ');
	document.getElementById('timec').selectedIndex = leftString(document.getElementById('NOW').value, ':');
