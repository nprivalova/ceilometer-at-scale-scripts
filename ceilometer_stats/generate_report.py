#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
import argparse

import glob
import json
import re

import mako.lookup
import mako.template


NAME_PATTERN = re.compile(r"(\A[a-zA-Z0-9_\- .]+)(/\d+)?/(.*\Z)")

DESCRIPTIONS = {"cpu util": "CPU usage expressed as the percentage of "
                            "time spent running during the entire "
                            "lifetime of a process.",
                "mem util": "Ratio of the process's resident set size "
                            "to the physical memory on the machine, "
                            "expressed as a percentage.",
                "virtual": "Virtual memory size of the process.",
                "total size": "Collection size in MB.",
                "file size": "Size of db files in MB.",
                "write rate": "Rate of records writing.",
                "total index size": "Total size of index."}


def get_template(template_dir, template_path):
    LOOKUP = mako.lookup.TemplateLookup(directories=template_dir)
    return LOOKUP.get_template(template_path)


def garmonic_mean(ts_values):
    l = len(ts_values)
    s = sum(1/value[1] for value in ts_values if value[1])
    return l/s if s else 0


def parse_line(line):
    raw = line.strip().split("\t")
    if len(raw) != 5:
        raise ValueError("Line has too few fields")
    type, node, name, ts, value = raw
    ts = int(ts)
    value = float(value)
    return type, node, name, ts, value


def format_name(namenode):
    name_arr = namenode.rsplit("/", 1)
    return name_arr[0].replace("_", " "), name_arr[1]


def get_value(type, value, prev_value):
    if type == "DELTA":
        return (value - prev_value)/5 if prev_value else 0
    return value


def prepare_data(log_file, count=400):
    if count <= 0:
        count = 100
    previous_values = {}
    statistics = {}

    data = {}
    with open(log_file, 'r') as fi:
        for line in fi:
            try:
                type, node, name, ts, v = parse_line(line)
                namenode = "%s/%s" % (name, node)
                value = get_value(type, v, previous_values.get(namenode))
                previous_values[namenode] = v
                data.setdefault(namenode, []).append((ts, value))
            except ValueError:
                continue
    for name, tss in data.iteritems():
        name, node = format_name(name)
        statistics.setdefault(name, {})[node] = []

        stats = {}
        tss = sorted(tss)
        interval = int(len(tss)/count) + 1
        start_ts = tss[0][0] - tss[0][0] % interval
        interval_ts = start_ts
        for ts, value in tss:
            ts = ts - ts % interval - start_ts
            stats.setdefault(ts, {})

            if ts != interval_ts:
                ts_dict = stats.get(interval_ts)
                if ts_dict:
                    gmean = (ts_dict["count"]/ts_dict["sum"]
                             if ts_dict["sum"] else 0)
                    statistics[name][node].append(
                        (interval_ts, gmean))
                interval_ts = ts
            stats[ts]["count"] = stats[ts].get("count", 0) + 1
            stats[ts]["sum"] = (stats[ts].get("sum", 0) +
                                (1./value) if value else 0)
        ts_dict = stats.get(interval_ts)
        if ts_dict:
            gmean = (ts_dict["count"]/ts_dict["sum"]
                             if ts_dict["sum"] else 0)
            statistics[name][node].append((interval_ts, gmean))

    return statistics


def _prepare_output(data):
    res = []
    items = data.items()
    for node, values in sorted(items):
        res.append({"key": node, "values": values,
                    "area": True})
    return res


def _process_results(results):
    output = []
    source_dict = {}

    for name, result in results.iteritems():

        groups = NAME_PATTERN.findall(name)
        if groups:
            cls = groups[0][0]
            name = groups[0][2]
        else:
            cls = "ceilometer stats"
            name = name
        description = ""
        for note, desc in DESCRIPTIONS.iteritems():
            if note in name or note in cls:
                description = desc
                break

        source_dict[name] = ""
        output.append({
            "cls": cls,
            "met": name,
            "name": name,
            "description": description,
            "iterations": {"iter": _prepare_output(result)},
        })
    source = json.dumps(source_dict, indent=2, sort_keys=True)
    scenarios = sorted(output, key=lambda r: "%s%s" % (r["cls"], r["name"]))
    return source, scenarios


def collect_stats_from_logs(dir, points=500):
    files = glob.glob("%s/*stats.log" % dir)
    statistics = {}
    for file in files:
        try:
            for meter, data in prepare_data(file, points).items():
                statistics.setdefault(meter, {}).update(data)
        except Exception as e:
            print "Failed to make stats from file %s. Error %s" % (file, e)
            continue
    return statistics

def generate_report(log_dir="/var/ceilometer_stats/", points=500,
                    template_dir="./template"):
    statistics = collect_stats_from_logs(log_dir, points)

    template = get_template(template_dir, "report.mako")
    source, scenarios = _process_results(statistics)
    return template.render(data=json.dumps(scenarios),
                           source=json.dumps(source))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",
                        help="HTML output with test results.",
                        default="/tmp/ceilometer_stats/ceilometer_stats.html")
    parser.add_argument("--chart-points",
                        type=int,
                        help="Count of points in result chart",
                        default=100,
                        dest="points")
    parser.add_argument("--logdir",
                        help="Directory with collected ceilometer loading "
                             "logs.",
                        default="/tmp/ceilometer_stats/")
    parser.add_argument("--templates-dir",
                        help="Directory with templates for output.",
                        default="./template",
                        dest="templates")
    args = parser.parse_args()
    template = generate_report(args.logdir, args.points, args.templates)
    with open(args.output, 'w') as fi:
        fi.write(template)

if __name__ == '__main__':
    main()