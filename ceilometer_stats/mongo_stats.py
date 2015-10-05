#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import argparse
import os
from os import path
import socket

import pymongo
import time

DELTA_METERS = ['inserted', 'deleted', 'updated', 'rate']

check = lambda name: any(i in name for i in DELTA_METERS)

def format_output(output):
    hostname = socket.gethostname()
    timestamp = time.time()
    return '\n'.join(
        "%(type)s\t%(node)s\t%(name)s\t%(ts).0f\t%(value)s\t" %
        dict(type="DELTA" if check(name) else "GAUGE",
             node=hostname, name=name, ts=timestamp,
             value=value)
        for name, value in output.items()
    )


def process_stats(db_stats, collection_stats, server_stats):
    output = {
        "db_file_size/ceilometer": db_stats.get("fileSize", 0)
    }
    for name, stats in collection_stats.items():
        collection_output = {
            "Collection_%s/total_size" % name: stats.get("storageSize", 0),
            "Collection_%s/total_index_size" % name:
                stats.get("totalIndexSize", 0),
            "Collection_%s/write_rate" % name: stats.get("count", 0),
            "Collection_%s/count" % name: stats.get("count", 0),
        }
        for index, size in stats.get("indexSize", {}).items():
            collection_output[
                "Collection_%s/index_%s_size" % (name, index)] = size

        for name, value in server_stats.items():
            output['MongoDB_document_rates/%s' % name] = value
        output.update(collection_output)

    return output


def get_stats(args):
    connection = pymongo.MongoClient(args.url)
    db = connection.ceilometer
    db_stats = db.command("dbstats",scale=2**20)
    collection_stats = {}
    for collection in db.collection_names(False):
        collection_stats[collection] = db.command("collstats", collection,
                                                   scale=2**20)
    server_stats = (db.command("serverStatus")
                    .get('metrics', {}).get("document"))
    return db_stats, collection_stats, server_stats


def recreate_file(result_file):
    directory = path.dirname(result_file)
    if directory:
        if not os.path.exists(directory):
            os.makedirs(directory)
    open(result_file, 'w').close()


def save_output(result_file, output):
    with open(result_file, 'a') as fio:
        fio.write(output)
        fio.write("\n")
        fio.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url",
                        default="mongodb://localhost:27000/ceilometer",
                        help="Url for mongodb connection.")
    parser.add_argument("--interval",
                        default=5,
                        type=int,
                        help="Interval between two measures (seconds).")
    parser.add_argument("--result",
                        default="/tmp/mongodb_stats.log",
                        help="Path for result log file.")
    args = parser.parse_args()
    recreate_file(args.result)

    while True:
        request_time = time.time()
        try:
            db_stats, collection_stats, server_stats = get_stats(args)
            output = process_stats(db_stats, collection_stats, server_stats)
            save_output(args.result, format_output(output))
        except Exception as e:
            print e

        duration = time.time() - request_time
        time.sleep(max(0, args.interval - duration))


if __name__ == '__main__':
    main()
