## -*- coding: utf-8 -*-
<%inherit file="/base.mako"/>

<%block name="html_attr"> ng-app="BenchmarkApp"</%block>

<%block name="title_text">Benchmark Task Report</%block>

<%block name="libs">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/nvd3/1.1.15-beta/nv.d3.min.css">
  <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/angularjs/1.3.3/angular.min.js"></script>
  <script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/d3/3.4.13/d3.min.js"></script>
  <script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/nvd3/1.1.15-beta/nv.d3.min.js"></script>
</%block>


<%block name="js_before">
    "use strict";
    if (typeof angular === "object") { angular.module("BenchmarkApp", []).controller(
      "BenchmarkController", ["$scope", "$location", function($scope, $location) {

      $scope.location = {
        /* This is a junior brother of angular's $location, that allows non-`#'
           symbol in uri, like `#/path/hash' instead of `#/path#hash' */
        _splitter: "/",
        normalize: function(str) {
          /* Remove unwanted characters from string */
          if (typeof str !== "string") { return "" }
          return str.replace(/[^\w\-\.]/g, "")
        },
        _parseUri: function(uriStr) {
          /* :returns: {path:string, hash:string} */
          var self = this;
          var obj = {path: "", hash: ""};
          angular.forEach(uriStr.split(self._splitter), function(v){
            var s = self.normalize(v);
            if (! s) { return }
            if (! this.path) { this.path = s } else if (! this.hash) { this.hash = s }
          }, obj)
          return obj
        },
        uri: function(obj) {
          /* Getter/Setter */
          if (! obj) { return this._parseUri($location.url()) }
          if (obj.path && obj.hash) {
            $location.url(obj.path + this._splitter + obj.hash)
          } else if (obj.path) {
            $location.url(obj.path)
          } else {
            $location.url("/")
          }
        },
        path: function(path, hash) {
          /* Getter/Setter */
          var uri = this.uri();
          if (path === "") { return this.uri({}) }
          path = this.normalize(path);
          if (! path) { return uri.path }
          uri.path = path;
          var _hash = this.normalize(hash);
          if (_hash || hash === "") { uri.hash = _hash }
          return this.uri(uri)
        },
        hash: function(hash) {
          /* Getter/Setter */
          var uri = this.uri();
          if (! hash) { return uri.hash }
          return this.uri({path:uri.path, hash:hash})
        }
      }

      /* Dispatch */

      $scope.route = function(uri) {
        if (! $scope.scenarios) {
          return
        }
        if (uri.path in $scope.scenarios_map) {
          $scope.view = {is_scenario:true};
          $scope.scenario = $scope.scenarios_map[uri.path];
          $scope.nav_idx = $scope.nav_map[uri.path];
          $scope.showTab(uri.hash);
        } else {
          $scope.scenario = undefined
          if (uri.path === "source") {
            $scope.view = {is_source:true}
          } else {
            $scope.view = {is_main:true}
          }
        }
      }

      $scope.$on("$locationChangeSuccess", function (event, newUrl, oldUrl) {
        $scope.route($scope.location.uri())
      });

      /* Navigation */

      $scope.showNav  = function(nav_idx) {
        $scope.nav_idx = nav_idx
      }

      /* Tabs */

      $scope.tabs = [
        {
          id: "overview",
          name: "Overview",
          visible: function(){ return !! $scope.scenario.iterations.pie.length }
        },{
          id: "details",
          name: "Details",
          visible: function(){ return !! $scope.scenario.atomic.pie.length }
        },{
          id: "output",
          name: "Output",
          visible: function(){ return !! $scope.scenario.output.length }
        },{
          id: "failures",
          name: "Failures",
          visible: function(){ return !! $scope.scenario.errors.length }
        },{
          id: "task",
          name: "Input task",
          visible: function(){ return !! $scope.scenario.config }
        }
      ];
      $scope.tabs_map = {};
      angular.forEach($scope.tabs,
                      function(tab){ this[tab.id] = tab }, $scope.tabs_map);

      $scope.showTab = function(tab_id) {
        $scope.tab = tab_id in $scope.tabs_map ? tab_id : "overview"
      }

      for (var i in $scope.tabs) {
        if ($scope.tabs[i].id === $scope.location.hash()) {
          $scope.tab = $scope.tabs[i].id
        }
        $scope.tabs[i].isVisible = function(){
          if ($scope.scenario) {
            if (this.visible()) {
              return true
            }
            /* If tab should be hidden but is selected - show another one */
            if (this.id === $scope.location.hash()) {
              for (var i in $scope.tabs) {
                var tab = $scope.tabs[i];
                if (tab.id != this.id && tab.visible()) {
                  $scope.tab = tab.id;
                  return false
                }
              }
            }
          }
          return false
        }
      }

      /* Charts */

      var Charts = {
        _render: function(selector, datum, chart){
          nv.addGraph(function() {
            d3.select(selector)
              .datum(datum)
              .transition()
              .duration(0)
              .call(chart);
            nv.utils.windowResize(chart.update)
          })
        },
        pie: function(selector, datum){
          var chart = nv.models.pieChart()
            .x(function(d) { return d.key })
            .y(function(d) { return d.value })
            .showLabels(true)
            .labelType("percent")
            .donut(true)
            .donutRatio(0.25)
            .donutLabelsOutside(true);
            this._render(selector, datum, chart)
        },
        stack: function(selector, datum){
          var chart = nv.models.lineChart()
            .margin({left: 100})  //Adjust chart margins to give the x-axis some breathing room.
                .useInteractiveGuideline(true)  //We want nice looking tooltips and a guideline!
                .transitionDuration(350)  //how fast do you want the lines to transition?
                .showLegend(true)       //Show the legend, allowing users to turn on/off line series.
                .showYAxis(true)        //Show the y-axis
                .showXAxis(true)
                .x(function(d) { return d[0]})
                .y(function(d) { return d[1]})
                .clipEdge(true);
          chart.xAxis
            .axisLabel("Test duration, s")
            .showMaxMin(false)
            .tickFormat(d3.format("d"));
          chart.yAxis
            .axisLabel("Value")
            .tickFormat(d3.format(",.2f"));
          this._render(selector, datum, chart)
        },
        histogram: function(selector, datum){
          var chart = nv.models.multiBarChart()
            .reduceXTicks(true)
            .showControls(false)
            .transitionDuration(0)
            .groupSpacing(0.05);
          chart.legend
            .radioButtonMode(true)
          chart.xAxis
            .axisLabel("Duration (seconds)")
            .tickFormat(d3.format(",.2f"));
          chart.yAxis
            .axisLabel("Iterations (frequency)")
            .tickFormat(d3.format("d"));
          this._render(selector, datum, chart)
        }
      };

      $scope.renderTotal = function() {
        if (! $scope.scenario) {
          return
        }
        Charts.stack("#total-stack", $scope.scenario.iterations.iter);
        Charts.pie("#total-pie", $scope.scenario.iterations.pie);

        if ($scope.scenario.iterations.histogram.length) {
          var idx = this.totalHistogramModel.value;
          Charts.histogram("#total-histogram",
                           [$scope.scenario.iterations.histogram[idx]])
        }
      }

      $scope.renderDetails = function() {
        if (! $scope.scenario) {
          return
        }
        Charts.stack("#atomic-stack", $scope.scenario.atomic.iter);
        Charts.pie("#atomic-pie", $scope.scenario.atomic.pie);
        if ($scope.scenario.atomic.histogram.length) {
          var atomic = [];
          var idx = this.atomicHistogramModel.value;
          for (var i in $scope.scenario.atomic.histogram) {
            atomic[i] = $scope.scenario.atomic.histogram[i][idx]
          }
          Charts.histogram("#atomic-histogram", atomic)
        }
      }

      $scope.renderOutput = function() {
        if ($scope.scenario) {
          Charts.stack("#output-stack", $scope.scenario.output)
        }
      }

      $scope.showError = function(message) {
          return (function (e) {
            e.style.display = "block";
            e.textContent = message
          })(document.getElementById("page-error"))
      }

      /* Initialization */

      angular.element(document).ready(function(){
        $scope.source = ${source};
        $scope.scenarios = ${data};
        if (! $scope.scenarios.length) {
          return $scope.showError("Benchmark has empty scenarios data")
        }
        $scope.histogramOptions = [];
        $scope.totalHistogramModel = {label:'', value:0};
        $scope.atomicHistogramModel = {label:'', value:0};

        /* Compose data mapping */

        $scope.nav = [];
        $scope.nav_map = {};
        $scope.scenarios_map = {};
        var scenario_ref = $scope.location.path();
        var met = [];
        var itr = 0;
        var cls_idx = 0;
        var prev_cls, prev_met;

        for (var idx in $scope.scenarios) {
          var sc = $scope.scenarios[idx];
          if (! prev_cls) {
            prev_cls = sc.cls
          }
          else if (prev_cls !== sc.cls) {
            $scope.nav.push({cls:prev_cls, met:met, idx:cls_idx});
            prev_cls = sc.cls;
            met = [];
            itr = 1;
            cls_idx += 1
          }

          if (prev_met !== sc.met) {
            itr = 1
          }

          sc.ref = $scope.location.normalize(sc.cls+"."+sc.met+(itr > 1 ? "-"+itr : ""));
          $scope.scenarios_map[sc.ref] = sc;
          $scope.nav_map[sc.ref] = cls_idx;
          var current_ref = $scope.location.path();
          if (sc.ref === current_ref) {
            scenario_ref = sc.ref
          }

          met.push({name:sc.name, itr:itr, idx:idx, ref:sc.ref});
          prev_met = sc.met;
          itr += 1

          /* Compose histograms options, from first suitable scenario */

          if (! $scope.histogramOptions.length && sc.iterations.histogram) {
            for (var i in sc.iterations.histogram) {
              $scope.histogramOptions.push({
                label: sc.iterations.histogram[i].method,
                value: i
              })
            }
            $scope.totalHistogramModel = $scope.histogramOptions[0];
            $scope.atomicHistogramModel = $scope.histogramOptions[0];
          }
        }

        if (met.length) {
          $scope.nav.push({cls:prev_cls, met:met, idx:cls_idx})
        }

        /* Start */

        var uri = $scope.location.uri();
        uri.path = scenario_ref;
        $scope.route(uri);
        $scope.$digest()
      });
    }])}
</%block>

<%block name="css">
    .aside { margin:0 20px 0 0; display:block; width:255px; float:left }
    .aside > div { margin-bottom: 15px }
    .aside > div div:first-child { border-top-left-radius:4px; border-top-right-radius:4px }
    .aside > div div:last-child { border-bottom-left-radius:4px; border-bottom-right-radius:4px }
    .nav-group { color:#678; background:#eee; border:1px solid #ddd; margin-bottom:-1px; display:block; padding:8px 9px; font-weight:bold; text-aligh:left; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; cursor:pointer }
    .nav-group.expanded { color:#469 }
    .nav-group.active { background:#428bca; background-image:linear-gradient(to bottom, #428bca 0px, #3278b3 100%); border-color:#3278b3; color:#fff }
    .nav-item { color:#555; background:#fff; border:1px solid #ddd; font-size:12px; display:block; margin-bottom:-1px; padding:8px 10px; text-aligh:left; text-overflow:ellipsis; white-space:nowrap; overflow:hidden; cursor:pointer }
    .nav-item:hover { background:#f8f8f8 }
    .nav-item.active, .nav-item.active:hover { background:#428bca; background-image:linear-gradient(to bottom, #428bca 0px, #3278b3 100%); border-color:#3278b3; color:#fff }

    .tabs { list-style:outside none none; margin:0 0 5px; padding:0; border-bottom:1px solid #ddd }
    .tabs:after { clear:both }
    .tabs li { float:left; margin-bottom:-1px; display:block; position:relative }
    .tabs li div { border:1px solid transparent; border-radius:4px 4px 0 0; line-height:20px; margin-right:2px; padding:10px 15px; color:#428bca }
    .tabs li div:hover { border-color:#eee #eee #ddd; background:#eee; cursor:pointer; }
    .tabs li.active div { background:#fff; border-color:#ddd #ddd transparent; border-style:solid; border-width:1px; color:#555; cursor:default }
    .failure-mesg { color:#900 }
    .failure-trace { color:#333; white-space:pre; overflow:auto }

    .chart { height:300px }
    .chart .chart-dropdown { float:right; margin:0 35px 0 }
    .chart.lesser { padding:0; margin:0; float:left; width:40% }
    .chart.larger { padding:0; margin:0; float:left; width:59% }
    .chart.larger { padding:0; margin:0; float:left; width:59% }

    .expandable { cursor:pointer }
    .clearfix { clear:both }
    .top-margin { margin-top:40px !important }
    .sortable > .arrow { display:inline-block; width:12px; height:inherit; color:#c90 }
    .content-main { margin:0 5px; display:block; float:left }
</%block>

<%block name="media_queries">
    @media only screen and (min-width: 320px)  { .content-wrap { width:900px  } .content-main { width:600px } }
    @media only screen and (min-width: 900px)  { .content-wrap { width:880px  } .content-main { width:590px } }
    @media only screen and (min-width: 1000px) { .content-wrap { width:980px  } .content-main { width:690px } }
    @media only screen and (min-width: 1100px) { .content-wrap { width:1080px } .content-main { width:790px } }
    @media only screen and (min-width: 1200px) { .content-wrap { width:1180px } .content-main { width:890px } }
</%block>

<%block name="body_attr"> ng-controller="BenchmarkController"</%block>

<%block name="header_text">benchmark results</%block>

<%block name="content">
    <p id="page-error" class="notify-error" style="display:none"></p>

    <div id="content-nav" class="aside" ng-show="scenarios.length" ng-cloack>
      <div>
        <div class="nav-group" title="{{n.cls}}"
             ng-repeat-start="n in nav track by $index"
             ng-click="showNav(n.idx)"
             ng-class="{expanded:n.idx==nav_idx}">
                <span ng-hide="n.idx==nav_idx">&#9658;</span>
                <span ng-show="n.idx==nav_idx">&#9660;</span>
                {{n.cls}}</div>
        <div class="nav-item" title="{{m.name}}"
             ng-show="n.idx==nav_idx"
             ng-class="{active:m.ref==scenario.ref}"
             ng-click="location.path(m.ref)"
             ng-repeat="m in n.met track by $index"
             ng-repeat-end>{{m.name}}</div>
      </div>
    </div>

    <div id="content-main" class="content-main" ng-show="scenarios.length" ng-cloak>


      <div ng-show="view.is_scenario">
        <h1><wbr>{{scenario.cls}}</h1>
        <ul class="tabs">
          <li ng-repeat="t in tabs"
              ng-show="t.isVisible()"
              ng-class="{active:t.id == tab}"
              ng-click="location.hash(t.id)">
            <div>{{t.name}}</div>
          </li>
          <div class="clearfix"></div>
        </ul>
        <div ng-include="tab"></div>

        <script>
        </script>
        <script type="text/ng-template" id="overview">


          <p> {{scenario.description}} &nbsp;
          {{renderTotal()}}</p>
          <div class="chart">
            <svg id="total-stack"></svg>
          </div>

        </script>

      </div>

    </div>
    <div class="clearfix"></div>
</%block>

<%block name="js_after">
    if (! window.angular) {(function(f){
      f(document.getElementById("content-nav"), "none");
      f(document.getElementById("content-main"), "none");
      f(document.getElementById("page-error"), "block").textContent = "Failed to load AngularJS framework"
    })(function(e, s){e.style.display = s; return e})}
</%block>
