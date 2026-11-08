/*
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
var showControllersOnly = false;
var seriesFilter = "";
var filtersOnlySampleSeries = true;

/*
 * Add header in statistics table to group metrics by category
 * format
 *
 */
function summaryTableHeader(header) {
    var newRow = header.insertRow(-1);
    newRow.className = "tablesorter-no-sort";
    var cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 1;
    cell.innerHTML = "Requests";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 3;
    cell.innerHTML = "Executions";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 7;
    cell.innerHTML = "Response Times (ms)";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 1;
    cell.innerHTML = "Throughput";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 2;
    cell.innerHTML = "Network (KB/sec)";
    newRow.appendChild(cell);
}

/*
 * Populates the table identified by id parameter with the specified data and
 * format
 *
 */
function createTable(table, info, formatter, defaultSorts, seriesIndex, headerCreator) {
    var tableRef = table[0];

    // Create header and populate it with data.titles array
    var header = tableRef.createTHead();

    // Call callback is available
    if(headerCreator) {
        headerCreator(header);
    }

    var newRow = header.insertRow(-1);
    for (var index = 0; index < info.titles.length; index++) {
        var cell = document.createElement('th');
        cell.innerHTML = info.titles[index];
        newRow.appendChild(cell);
    }

    var tBody;

    // Create overall body if defined
    if(info.overall){
        tBody = document.createElement('tbody');
        tBody.className = "tablesorter-no-sort";
        tableRef.appendChild(tBody);
        var newRow = tBody.insertRow(-1);
        var data = info.overall.data;
        for(var index=0;index < data.length; index++){
            var cell = newRow.insertCell(-1);
            cell.innerHTML = formatter ? formatter(index, data[index]): data[index];
        }
    }

    // Create regular body
    tBody = document.createElement('tbody');
    tableRef.appendChild(tBody);

    var regexp;
    if(seriesFilter) {
        regexp = new RegExp(seriesFilter, 'i');
    }
    // Populate body with data.items array
    for(var index=0; index < info.items.length; index++){
        var item = info.items[index];
        if((!regexp || filtersOnlySampleSeries && !info.supportsControllersDiscrimination || regexp.test(item.data[seriesIndex]))
                &&
                (!showControllersOnly || !info.supportsControllersDiscrimination || item.isController)){
            if(item.data.length > 0) {
                var newRow = tBody.insertRow(-1);
                for(var col=0; col < item.data.length; col++){
                    var cell = newRow.insertCell(-1);
                    cell.innerHTML = formatter ? formatter(col, item.data[col]) : item.data[col];
                }
            }
        }
    }

    // Add support of columns sort
    table.tablesorter({sortList : defaultSorts});
}

$(document).ready(function() {

    // Customize table sorter default options
    $.extend( $.tablesorter.defaults, {
        theme: 'blue',
        cssInfoBlock: "tablesorter-no-sort",
        widthFixed: true,
        widgets: ['zebra']
    });

    var data = {"OkPercent": 99.13669064748201, "KoPercent": 0.8633093525179856};
    var dataset = [
        {
            "label" : "FAIL",
            "data" : data.KoPercent,
            "color" : "#FF6347"
        },
        {
            "label" : "PASS",
            "data" : data.OkPercent,
            "color" : "#9ACD32"
        }];
    $.plot($("#flot-requests-summary"), dataset, {
        series : {
            pie : {
                show : true,
                radius : 1,
                label : {
                    show : true,
                    radius : 3 / 4,
                    formatter : function(label, series) {
                        return '<div style="font-size:8pt;text-align:center;padding:2px;color:white;">'
                            + label
                            + '<br/>'
                            + Math.round10(series.percent, -2)
                            + '%</div>';
                    },
                    background : {
                        opacity : 0.5,
                        color : '#000'
                    }
                }
            }
        },
        legend : {
            show : true
        }
    });

    // Creates APDEX table
    createTable($("#apdexTable"), {"supportsControllersDiscrimination": true, "overall": {"data": [0.9891467065868264, 500, 1500, "Total"], "isController": false}, "titles": ["Apdex", "T (Toleration threshold)", "F (Frustration threshold)", "Label"], "items": [{"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T07_AddChairToCart"], "isController": true}, {"data": [0.9629629629629629, 500, 1500, "S01_Browse_And_Checkout_T11_SubmitOrder"], "isController": true}, {"data": [0.9814814814814815, 500, 1500, "SubmitOrder-0"], "isController": false}, {"data": [0.9895833333333334, 500, 1500, "S01_Browse_And_Checkout_T03_OpenTableProductCard"], "isController": true}, {"data": [1.0, 500, 1500, "SubmitOrder-1"], "isController": false}, {"data": [1.0, 500, 1500, "OpenCheckout"], "isController": false}, {"data": [1.0, 500, 1500, "AddChairToCart"], "isController": false}, {"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T10_LoadStateDropdown"], "isController": true}, {"data": [0.97, 500, 1500, "S01_Browse_And_Checkout_T02_NavigateToTables"], "isController": true}, {"data": [1.0, 500, 1500, "LoadStateDropdown"], "isController": false}, {"data": [0.9629629629629629, 500, 1500, "SubmitOrder"], "isController": false}, {"data": [0.9894736842105263, 500, 1500, "S01_Browse_And_Checkout_T04_AddTableToCart"], "isController": true}, {"data": [1.0, 500, 1500, "NavigateToChairs"], "isController": false}, {"data": [0.9894736842105263, 500, 1500, "AddTableToCart"], "isController": false}, {"data": [1.0, 500, 1500, "OpenApplication"], "isController": false}, {"data": [1.0, 500, 1500, "OpenCart"], "isController": false}, {"data": [0.9787234042553191, 500, 1500, "OpenChairProductCard"], "isController": false}, {"data": [0.97, 500, 1500, "NavigateToTables"], "isController": false}, {"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T05_NavigateToChairs"], "isController": true}, {"data": [0.9787234042553191, 500, 1500, "S01_Browse_And_Checkout_T06_OpenChairProductCard"], "isController": true}, {"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T09_OpenCheckout"], "isController": true}, {"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T08_OpenCart"], "isController": true}, {"data": [1.0, 500, 1500, "S01_Browse_And_Checkout_T01_OpenApplication"], "isController": true}, {"data": [0.9895833333333334, 500, 1500, "OpenTableProductCard"], "isController": false}]}, function(index, item){
        switch(index){
            case 0:
                item = item.toFixed(3);
                break;
            case 1:
            case 2:
                item = formatDuration(item);
                break;
        }
        return item;
    }, [[0, 0]], 3);

    // Create statistics table
    createTable($("#statisticsTable"), {"supportsControllersDiscrimination": true, "overall": {"data": ["Total", 695, 6, 0.8633093525179856, 184.15539568345318, 1, 925, 177.0, 269.4, 349.39999999999986, 480.15999999999985, 1.1748100442032843, 9.697734357171834, 1.4025351386529408], "isController": false}, "titles": ["Label", "#Samples", "FAIL", "Error %", "Average", "Min", "Max", "Median", "90th pct", "95th pct", "99th pct", "Transactions/s", "Received", "Sent"], "items": [{"data": ["S01_Browse_And_Checkout_T07_AddChairToCart", 46, 0, 0.0, 99.84782608695652, 65, 229, 84.0, 133.70000000000013, 203.34999999999997, 229.0, 0.0834297612095139, 0.057368587924086174, 0.07634503284593426], "isController": true}, {"data": ["S01_Browse_And_Checkout_T11_SubmitOrder", 27, 0, 0.0, 443.55555555555554, 355, 925, 417.0, 513.5999999999999, 804.5999999999993, 925.0, 0.050954740866834505, 0.5011950184191952, 0.3530764720966178], "isController": true}, {"data": ["SubmitOrder-0", 27, 0, 0.0, 291.03703703703707, 227, 785, 260.0, 378.5999999999999, 669.7999999999994, 785.0, 0.05102272211891696, 0.025319435310747273, 0.3216085007634511], "isController": false}, {"data": ["S01_Browse_And_Checkout_T03_OpenTableProductCard", 96, 1, 1.0416666666666667, 209.71875, 2, 338, 209.5, 250.79999999999998, 288.74999999999994, 338.0, 0.16596506089707572, 1.875517965501742, 0.12433535639268026], "isController": true}, {"data": ["SubmitOrder-1", 27, 0, 0.0, 151.74074074074073, 119, 231, 142.0, 187.4, 214.1999999999999, 231.0, 0.05103082261686059, 0.476619909675444, 0.03194409892324964], "isController": false}, {"data": ["OpenCheckout", 27, 0, 0.0, 142.40740740740742, 100, 182, 144.0, 171.4, 180.0, 182.0, 0.05139205859456043, 0.7162303467012959, 0.03799198081648657], "isController": false}, {"data": ["AddChairToCart", 46, 0, 0.0, 99.84782608695652, 65, 229, 84.0, 133.70000000000013, 203.34999999999997, 229.0, 0.0834300638421358, 0.05736879602256239, 0.07634530977945443], "isController": false}, {"data": ["S01_Browse_And_Checkout_T10_LoadStateDropdown", 27, 0, 0.0, 67.33333333333334, 47, 86, 67.0, 79.6, 86.0, 86.0, 0.050991116214419534, 0.04864148217010636, 0.04058374972143742], "isController": true}, {"data": ["S01_Browse_And_Checkout_T02_NavigateToTables", 100, 3, 3.0, 182.69000000000003, 1, 298, 183.0, 214.8, 244.69999999999993, 297.70999999999987, 0.17226736584248215, 1.8876987292482423, 0.12255039843288376], "isController": true}, {"data": ["LoadStateDropdown", 27, 0, 0.0, 67.33333333333334, 47, 86, 67.0, 79.6, 86.0, 86.0, 0.050991116214419534, 0.04864148217010636, 0.04058374972143742], "isController": false}, {"data": ["SubmitOrder", 27, 0, 0.0, 443.55555555555554, 355, 925, 417.0, 513.5999999999999, 804.5999999999993, 925.0, 0.05100710699024064, 0.5017100959122527, 0.3534393283450272], "isController": false}, {"data": ["S01_Browse_And_Checkout_T04_AddTableToCart", 95, 1, 1.0526315789473684, 105.12631578947364, 2, 377, 102.0, 137.20000000000002, 169.19999999999982, 377.0, 0.16488303718025707, 0.1156791456368477, 0.1448269004722597], "isController": true}, {"data": ["NavigateToChairs", 48, 0, 0.0, 186.85416666666669, 147, 322, 178.0, 235.0, 258.89999999999986, 322.0, 0.0845624246865905, 0.901381563387465, 0.06398611854947253], "isController": false}, {"data": ["AddTableToCart", 95, 1, 1.0526315789473684, 105.12631578947364, 2, 377, 102.0, 137.20000000000002, 169.19999999999982, 377.0, 0.16488360952784278, 0.11567954718621781, 0.14482740320030407], "isController": false}, {"data": ["OpenApplication", 100, 0, 0.0, 248.11, 175, 452, 241.0, 293.9, 344.74999999999994, 451.9, 0.17241765763715394, 2.084670917192972, 0.0919336338573106], "isController": false}, {"data": ["OpenCart", 28, 0, 0.0, 128.99999999999997, 95, 156, 127.5, 147.3, 153.29999999999998, 156.0, 0.05076528669695662, 0.49545198839016025, 0.0382811196873221], "isController": false}, {"data": ["OpenChairProductCard", 47, 1, 2.127659574468085, 170.63829787234042, 2, 242, 171.0, 218.20000000000002, 232.39999999999992, 242.0, 0.0852999199632666, 0.9635215090780894, 0.0630479981061603], "isController": false}, {"data": ["NavigateToTables", 100, 3, 3.0, 182.69000000000003, 1, 298, 183.0, 214.8, 244.69999999999993, 297.70999999999987, 0.1722744883878381, 1.8877767778081171, 0.12255546538660979], "isController": false}, {"data": ["S01_Browse_And_Checkout_T05_NavigateToChairs", 48, 0, 0.0, 186.85416666666669, 147, 322, 178.0, 235.0, 258.89999999999986, 322.0, 0.08456227571177652, 0.9013799754108758, 0.06398600582422674], "isController": true}, {"data": ["S01_Browse_And_Checkout_T06_OpenChairProductCard", 47, 1, 2.127659574468085, 170.63829787234042, 2, 242, 171.0, 218.20000000000002, 232.39999999999992, 242.0, 0.0852999199632666, 0.9635215090780894, 0.0630479981061603], "isController": true}, {"data": ["S01_Browse_And_Checkout_T09_OpenCheckout", 27, 0, 0.0, 142.40740740740742, 100, 182, 144.0, 171.4, 180.0, 182.0, 0.05139205859456043, 0.7162303467012959, 0.03799198081648657], "isController": true}, {"data": ["S01_Browse_And_Checkout_T08_OpenCart", 28, 0, 0.0, 128.99999999999997, 95, 156, 127.5, 147.3, 153.29999999999998, 156.0, 0.05076528669695662, 0.49545198839016025, 0.0382811196873221], "isController": true}, {"data": ["S01_Browse_And_Checkout_T01_OpenApplication", 100, 0, 0.0, 248.11, 175, 452, 241.0, 293.9, 344.74999999999994, 451.9, 0.17237159178270148, 2.084113943224245, 0.09190907139976073], "isController": true}, {"data": ["OpenTableProductCard", 96, 1, 1.0416666666666667, 209.71875, 2, 338, 209.5, 250.79999999999998, 288.74999999999994, 338.0, 0.16596534781842007, 1.875521207907903, 0.1243355713443539], "isController": false}]}, function(index, item){
        switch(index){
            // Errors pct
            case 3:
                item = item.toFixed(2) + '%';
                break;
            // Mean
            case 4:
            // Mean
            case 7:
            // Median
            case 8:
            // Percentile 1
            case 9:
            // Percentile 2
            case 10:
            // Percentile 3
            case 11:
            // Throughput
            case 12:
            // Kbytes/s
            case 13:
            // Sent Kbytes/s
                item = item.toFixed(2);
                break;
        }
        return item;
    }, [[0, 0]], 0, summaryTableHeader);

    // Create error table
    createTable($("#errorsTable"), {"supportsControllersDiscrimination": false, "titles": ["Type of error", "Number of errors", "% in errors", "% in all samples"], "items": [{"data": ["Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 6, 100.0, 0.8633093525179856], "isController": false}]}, function(index, item){
        switch(index){
            case 2:
            case 3:
                item = item.toFixed(2) + '%';
                break;
        }
        return item;
    }, [[1, 1]]);

        // Create top5 errors by sampler
    createTable($("#top5ErrorsBySamplerTable"), {"supportsControllersDiscrimination": false, "overall": {"data": ["Total", 695, 6, "Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 6, "", "", "", "", "", "", "", ""], "isController": false}, "titles": ["Sample", "#Samples", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors"], "items": [{"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": ["AddTableToCart", 95, 1, "Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 1, "", "", "", "", "", "", "", ""], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": ["OpenChairProductCard", 47, 1, "Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 1, "", "", "", "", "", "", "", ""], "isController": false}, {"data": ["NavigateToTables", 100, 3, "Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 3, "", "", "", "", "", "", "", ""], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": ["OpenTableProductCard", 96, 1, "Non HTTP response code: org.apache.http.NoHttpResponseException/Non HTTP response message: 172.17.0.1:80 failed to respond", 1, "", "", "", "", "", "", "", ""], "isController": false}]}, function(index, item){
        return item;
    }, [[0, 0]], 0);

});
