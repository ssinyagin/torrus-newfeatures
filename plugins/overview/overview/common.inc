<!-- modifiers & view are not user editable fields!!! -->
<modifiers>NOW=<%= $Request->Params('NOW') %>&amp;SHOWHIDDEN=<%= $Request->Params('SHOWHIDDEN') %>&amp;AUTOSCALE=<%= $Request->Params('AUTOSCALE') %>&amp;WINDOW=<%= $Request->Params('WINDOW') %>&amp;CF=<%= $Request->Params('CF') %>&amp;STRETCH=<%= $Request->Params('STRETCH') %></modifiers>
<view><%= $Request->Params('WINDOW') %><%= $Request->Params('AUTOSCALE')? 'Auto' : '' %></view>
