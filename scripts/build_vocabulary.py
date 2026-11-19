"""Build the shared offline vocabulary from ECDICT (MIT).

Usage: python3 scripts/build_vocabulary.py /path/to/ecdict.csv
The source CSV is not shipped; the compact, attributed derivative is bundled.
"""
import csv
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TAGS = {'zk', 'gk', 'cet4', 'cet6', 'ky', 'ielts', 'toefl'}


def main():
    entries = {}
    with open(sys.argv[1], encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            word = row['word'].strip().lower()
            tags = sorted(set(row.get('tag', '').split()) & TAGS)
            if not tags or not re.fullmatch(r"[a-z]+(?:[-'][a-z]+)*", word):
                continue
            translation = row.get('translation', '').replace('\\n', '\n').strip()
            if not translation:
                continue
            entries[word] = {'translation': translation, 'tags': tags}
    target = ROOT / 'assets/data/vocabulary.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({
        'version': 1,
        'source': 'https://github.com/skywind3000/ECDICT',
        'license': 'MIT',
        'entries': entries,
    }, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(f'Built {len(entries)} attributed vocabulary entries')


if __name__ == '__main__':
    main()
