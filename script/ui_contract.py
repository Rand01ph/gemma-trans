#!/usr/bin/env python3
"""UI contract validation. Baselines are never updated by this command."""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'docs/ui/ui-contract.json'


def validate(contract, sample):
    errors = []
    scene = sample['scene']
    elements = {e['id']: e for e in sample['elements']}
    for rule in contract['elements']:
        if scene not in rule['scenes']:
            continue
        element = elements.get(rule['id'])
        if not element:
            errors.append(f"{scene}: missing {rule['id']}")
            continue
        x, y, w, h = element['frame']
        if w <= 0 or h <= 0:
            errors.append(f"{scene}: invisible {rule['id']}")
        if 'contains' in rule and rule['contains'] not in element['text']:
            errors.append(f"{scene}: wrong text {rule['id']}: {element['text']!r}")
        if rule.get('fullyVisible', False):
            width, height = sample['width'] / sample['scale'], sample['height'] / sample['scale']
            if x < -1 or y < -1 or x + w > width + 1 or y + h > height + 1:
                errors.append(f"{scene}: clipped {rule['id']}")
    for relation in contract['relations']:
        if scene not in relation['scenes']:
            continue
        a, b = elements.get(relation['first']), elements.get(relation['second'])
        if a and b and relation['axis'] == 'x' and a['frame'][0] + a['frame'][2] > b['frame'][0] + 1:
            errors.append(f"{scene}: overlap/order {relation['first']} -> {relation['second']}")
        if a and b and relation['axis'] == 'y' and a['frame'][1] + a['frame'][3] > b['frame'][1] + 1:
            errors.append(f"{scene}: vertical order {relation['first']} -> {relation['second']}")
        if a and b and relation['axis'] == 'centerY' and abs(a['frame'][1]+a['frame'][3]/2 - b['frame'][1]-b['frame'][3]/2) > 1:
            errors.append(f"{scene}: row alignment {relation['first']} -> {relation['second']}")
    return errors


def compare(contract, baseline, current, output):
    from PIL import Image, ImageChops, ImageDraw
    errors = []
    output.mkdir(parents=True, exist_ok=True)
    for scene in contract['scenes']:
        for appearance in contract['appearances']:
            name = f'{scene}-{appearance}'
            a, b = baseline / (name + '.json'), current / (name + '.json')
            if not a.exists() or not b.exists():
                errors.append(f'{name}: missing baseline/capture'); continue
            original, actual = json.loads(a.read_text()), json.loads(b.read_text())
            errors.extend(validate(contract, actual))
            if any(original[k] != actual[k] for k in ['os', 'scale', 'font', 'width', 'height']):
                errors.append(f'{name}: ENVIRONMENT MISMATCH - cannot accept'); continue
            old = {e['id']: e for e in original['elements']}
            new = {e['id']: e for e in actual['elements']}
            for identifier, element in old.items():
                if identifier not in new:
                    errors.append(f'{name}: removed {identifier}'); continue
                candidate = new[identifier]
                if element['text'] != candidate['text'] or element['enabled'] != candidate['enabled']:
                    errors.append(f'{name}: content/state changed {identifier}')
                if any(abs(x-y) > 1 for x,y in zip(element['frame'], candidate['frame'])):
                    errors.append(f'{name}: geometry changed {identifier}')
            if new.keys() - old.keys():
                errors.append(f'{name}: added elements {sorted(new.keys()-old.keys())}')
            before = Image.open(a.with_suffix('.png')).convert('RGB')
            after = Image.open(b.with_suffix('.png')).convert('RGB')
            diff = ImageChops.difference(before, after)
            # Small antialiasing noise tolerated; no UI region is masked.
            pixels = list(diff.getdata())
            changed = sum(max(pixel) > 16 for pixel in pixels) / len(pixels)
            if changed > 0.002:
                errors.append(f'{name}: pixel difference {changed:.2%}')
            diff.save(output / (name + '-diff.png'))
            annotated = after.copy()
            draw = ImageDraw.Draw(annotated)
            index = []
            for number, element in enumerate(actual['elements'], 1):
                x,y,w,h = [v * actual['scale'] for v in element['frame']]
                draw.rectangle([x,y,x+w,y+h], outline='red', width=2)
                draw.text((x+2,y+2), str(number), fill='red')
                index.append(f'{number}. {element["id"]}: {element["text"][:80]}')
            annotated.save(output / (name + '-annotated.png'))
            (output / (name + '-index.txt')).write_text('\n'.join(index))
    (output / 'result.json').write_text(json.dumps({'passed': not errors, 'errors': errors}, indent=2, ensure_ascii=False))
    return errors


def check_source(contract):
    sources = "\n".join(p.read_text() for p in (ROOT/'App/GemmaTrans').rglob('*.swift'))
    for rule in contract['elements']:
        identifier = rule['id']
        if identifier.startswith('settings.model.'):
            needle = '"settings.model.'
        elif identifier.startswith('settings.field.'):
            needle = '"settings.field.'
        elif identifier.startswith('settings.toggle.'):
            needle = '"settings.toggle.'
        else:
            needle = '"' + identifier + '"'
        if needle not in sources:
            raise SystemExit(f'UI contract identifier removed from source: {identifier}')
    for identifier in contract['menu']['identifiers']:
        if '"'+identifier+'"' not in sources:
            raise SystemExit(f'Menu identifier removed: {identifier}')


def self_test(contract):
    # Deliberate regressions must fail before relying on screenshots.
    sample = {'scene':'panel-completed','width':1000,'height':500,'scale':1,'elements':[]}
    for n, rule in enumerate(r for r in contract['elements'] if 'panel-completed' in r['scenes']):
        sample['elements'].append({'id':rule['id'],'text':rule.get('contains',''),'enabled':True,'frame':[n*70,10,60,20]})
    # Arrange direction and rate as declared regardless of contract list order.
    lookup = {e['id']:e for e in sample['elements']}
    lookup['panel.result']['frame'] = [10,10,60,20]
    lookup['panel.copy']['frame'] = [10,50,20,20]
    lookup['panel.speak']['frame'] = [40,50,20,20]
    lookup['panel.rate']['frame'] = [170,50,60,20]
    assert not validate(contract, sample), validate(contract, sample)
    for identifier in ['panel.rate', 'panel.copy']:
        broken = {**sample, 'elements':[e for e in sample['elements'] if e['id'] != identifier]}
        assert any(identifier in e for e in validate(contract, broken)), identifier
    lookup['panel.rate']['frame'][0] = 40
    assert any('overlap' in e for e in validate(contract, sample))
    print('PASS: missing rate, removed copy, overlapping layout are rejected')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=pathlib.Path)
    parser.add_argument('--current', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT/'App/build/ui-diff')
    args = parser.parse_args()
    contract = json.loads(CONTRACT.read_text())
    check_source(contract)
    self_test(contract)
    if args.current and args.baseline:
        errors = compare(contract, args.baseline, args.current, args.output)
        if errors:
            print('\n'.join(errors)); return 1
        print('PASS: all UI scenes match')
    return 0

if __name__ == '__main__':
    sys.exit(main())
