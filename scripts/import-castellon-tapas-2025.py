#!/usr/bin/env python3
"""Dry-run by default importer for the authoritative 2025 Castellón source files.

Use --apply only after the Storage migration has been applied and with dates supplied
by the dataset owner. It authenticates as an existing festival administrator; it does
not use a service-role key or a database password.
"""
import argparse, getpass, json, mimetypes, os, re, sys
from pathlib import Path
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from zipfile import ZipFile
from xml.etree import ElementTree as ET

ROOT = Path("/home/k/Documents/tapas map '25/GUÍA RUTA DE TAPAS CS 2025")
DEFAULT_BOOK = ROOT / 'Castellon_Tapas_2025_complete_with_photos.xlsx'
DEFAULT_PHOTOS = ROOT / 'tapas dishes pics' / 'tapas_pics.zip'
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
TIME = re.compile(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})')
ROW_57 = {'name': '57. BLACK AND WHITE', 'latitude': 39.985940893314385, 'longitude': -0.030836789493540136}


def column(ref): return re.match(r'[A-Z]+', ref).group()
def xlsx_rows(path, sheet):
    with ZipFile(path) as archive:
        shared = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            root = ET.fromstring(archive.read('xl/sharedStrings.xml'))
            shared = [''.join(t.text or '' for t in item.iterfind('.//m:t', NS)) for item in root.findall('m:si', NS)]
        root = ET.fromstring(archive.read(sheet)); result = []
        for row in root.findall('.//m:sheetData/m:row', NS):
            values = {}
            for cell in row.findall('m:c', NS):
                value = cell.find('m:v', NS); text = '' if value is None else value.text or ''
                if cell.attrib.get('t') == 's' and text: text = shared[int(text)]
                elif cell.attrib.get('t') == 'inlineStr': text = ''.join(t.text or '' for t in cell.iterfind('.//m:t', NS))
                values[column(cell.attrib['r'])] = text
            result.append(values)
        return result

def source(book, photos):
    guide = xlsx_rows(book, 'xl/worksheets/sheet1.xml'); mapping = xlsx_rows(book, 'xl/worksheets/sheet3.xml')
    h, mh = guide[0], mapping[0]
    venues = [{h[k]: v for k, v in row.items()} for row in guide[1:] if any(row.values())]
    images = [{mh[k]: v for k, v in row.items()} for row in mapping[1:] if any(row.values())]
    image_map = {item['Import filename']: item['Original image'] for item in images}
    with ZipFile(photos) as archive: files = {Path(item).name for item in archive.namelist() if not item.endswith('/')}
    if len(venues) != 62 or len(images) != 124 or len(image_map) != 124: raise ValueError('Source counts are not 62 establishments and 124 mapped tapas.')
    photo_names = [v['Tapa 1 photo'] for v in venues] + [v['Tapa 2 photo'] for v in venues]
    if len(set(photo_names)) != 124 or set(photo_names) != set(image_map) or not set(image_map.values()).issubset(files): raise ValueError('Spreadsheet/photo archive mapping is incomplete.')
    return venues, image_map

def hours(venue):
    structured, exceptions = {}, []
    for index, day in enumerate(DAYS, 1):
        raw = venue[day].strip()
        if not raw: continue
        periods = []
        for start_h, start_m, end_h, end_m in TIME.findall(raw):
            if max(int(start_h), int(end_h)) > 23 or max(int(start_m), int(end_m)) > 59: raise ValueError(f'Invalid time in {venue["No."]} {day}: {raw}')
            start, end = f'{int(start_h):02}:{int(start_m):02}', f'{int(end_h):02}:{int(end_m):02}'
            if start == end: raise ValueError(f'Equal opening-hour times in {venue["No."]} {day}: {raw}')
            periods.append([start, end])
        remainder = ' '.join(TIME.sub('', raw).replace('/', ' ').split()).lower()
        if raw.lower() == 'closed / not listed': structured[str(index)] = []
        elif periods: structured[str(index)] = periods
        elif remainder not in ('closed', 'not listed', 'closed not listed'): raise ValueError(f'Unparseable opening hours in {venue["No."]} {day}: {raw}')
        if remainder and remainder not in ('closed', 'not listed', 'closed not listed'):
            exceptions.append(f'{day}: {raw}')
    return structured or None, '\n'.join(exceptions) or None

def load_env():
    for line in Path('.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1); os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))

class SupabaseHttpError(RuntimeError):
    def __init__(self, status, payload):
        self.status = status
        self.payload = payload
        super().__init__(f'HTTP {status}: {payload}')

def request(url, headers, method='GET', body=None, allowed=(200, 201, 204)):
    data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
    req = Request(url, data=data, method=method, headers=headers)
    try:
        with urlopen(req, timeout=60) as response:
            payload = response.read(); return response.status, json.loads(payload) if payload else None
    except HTTPError as exc:
        raw_payload = exc.read().decode(errors='replace')
        try:
            payload = json.loads(raw_payload)
        except json.JSONDecodeError:
            payload = {'message': raw_payload}
        if exc.code in allowed: return exc.code, payload
        raise SupabaseHttpError(exc.code, payload) from exc

def db_client():
    load_env(); base = os.environ['NUXT_PUBLIC_SUPABASE_URL'].rstrip('/'); key = os.environ['NUXT_PUBLIC_SUPABASE_KEY']
    email = input('Festival administrator email: ').strip(); password = getpass.getpass('Festival administrator password: ')
    _, auth = request(base + '/auth/v1/token?grant_type=password', {'apikey': key, 'Content-Type': 'application/json'}, 'POST', {'email': email, 'password': password})
    token = auth['access_token']; headers = {'apikey': key, 'Authorization': f'Bearer {token}', 'Accept-Profile': 'festival', 'Content-Profile': 'festival', 'Content-Type': 'application/json', 'Prefer': 'return=representation'}
    print('Import login successful.\nI am processing the import... sit tight.', flush=True)
    return base, headers

def select(base, headers, table, params):
    _, result = request(base + '/rest/v1/' + table + '?' + urlencode(params, safe=',().'), headers)
    return result or []
def one_or_none(rows, label):
    if len(rows) > 1: raise ValueError(f'Duplicate {label} rows already exist; refusing import.')
    return rows[0] if rows else None
def save(base, headers, table, payload, existing=None):
    if existing: _, result = request(base + '/rest/v1/' + table + '?id=eq.' + quote(existing['id']), headers, 'PATCH', payload)
    else: _, result = request(base + '/rest/v1/' + table, headers, 'POST', payload)
    return result[0]

def upload(base, headers, archive, original, destination):
    # Storage does not offer a reliable HEAD check for public objects. Object keys
    # are deterministic, so a non-upserting authenticated upload is idempotent:
    # the first run creates it and later runs receive HTTP 409 and skip it.
    content = archive.read(original); content_type = mimetypes.guess_type(original)[0] or 'application/octet-stream'
    upload_headers = {**headers, 'Content-Type': content_type, 'x-upsert': 'false'}
    try:
        request(base + '/storage/v1/object/festival-images/' + quote(destination, safe='/'), upload_headers, 'POST', content)
        return True
    except SupabaseHttpError as exc:
        # Some Storage deployments wrap a duplicate-object response in HTTP 400
        # while retaining the canonical statusCode/code inside the JSON payload.
        if exc.payload.get('code') == 'KeyAlreadyExists' or exc.payload.get('statusCode') == 409:
            return False
        raise

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--apply', action='store_true'); parser.add_argument('--festival-year', type=int, default=2025); parser.add_argument('--start-date', default='2026-09-01'); parser.add_argument('--end-date', default='2026-09-30'); parser.add_argument('--book', type=Path, default=DEFAULT_BOOK); parser.add_argument('--photos', type=Path, default=DEFAULT_PHOTOS)
    args = parser.parse_args(); venues, image_map = source(args.book, args.photos)
    for venue in venues: hours(venue)
    if not args.apply:
        print(f'Dry run passed: 1 festival ({args.start_date} to {args.end_date}, reviews enabled), 62 establishments, 124 tapas, 124 mapped photos. No network or database access occurred.'); return
    base, headers = db_client()
    slug = 'castellon-tapas-2025'
    festival = one_or_none(select(base, headers, 'festivals', {'select':'id','slug':'eq.' + slug}), 'festival slug')
    festival_payload = {'slug':slug,'name_en':'Castellón Tapas Festival 2025','name_es':None,'festival_year':args.festival_year,'start_date':args.start_date,'end_date':args.end_date,'default_tapa_price':5,'currency_code':'EUR','city':'Castellón de la Plana','timezone':'Europe/Madrid','default_language':'en','publication_status':'published','reviews_enabled':True}
    festival = save(base, headers, 'festivals', festival_payload, festival); festival_id = festival['id']
    definition = one_or_none(select(base, headers, 'field_definitions', {'select':'id','festival_id':'eq.'+festival_id,'applies_to':'eq.establishment','key':'eq.instagram'}), 'Instagram field definition')
    definition = save(base, headers, 'field_definitions', {'festival_id':festival_id,'key':'instagram','label_en':'Instagram','label_es':'Instagram','field_type':'text','applies_to':'establishment','required':False,'active':True,'sort_order':0}, definition)
    uploaded = 0
    processed_photos = 0
    with ZipFile(args.photos) as archive:
      for establishment_index, venue in enumerate(venues, 1):
        if establishment_index % 10 == 0 or establishment_index == len(venues):
          print(f'Processing establishments: {establishment_index}/{len(venues)}', flush=True)
        no = int(venue['No.']); name = ROW_57['name'] if no == 57 else venue['Festival bar number + name']
        lat = ROW_57['latitude'] if no == 57 else float(venue['GPS latitude']); lon = ROW_57['longitude'] if no == 57 else float(venue['GPS longitude'])
        opening, note = hours(venue)
        existing = one_or_none(select(base, headers, 'establishments', {'select':'id','festival_id':'eq.'+festival_id,'name':'eq.'+name}), f'establishment {name}')
        establishment = save(base, headers, 'establishments', {'festival_id':festival_id,'name':name,'address':venue['Address'],'latitude':lat,'longitude':lon,'phone':venue['Phone'] or None,'opening_hours':opening,'hours_notes_es':note,'is_published':True,'participation_status':'active','closure_status':'normal','sort_order':no-1}, existing)
        handle = venue['Instagram'].strip()
        if handle:
          value = one_or_none(select(base, headers, 'field_values', {'select':'id','field_definition_id':'eq.'+definition['id'],'establishment_id':'eq.'+establishment['id']}), f'Instagram value for {name}')
          save(base, headers, 'field_values', {'field_definition_id':definition['id'],'establishment_id':establishment['id'],'value':{'en': handle}}, value)
        for position in (1, 2):
          spanish = venue[f'Tapa {position}']; photo = venue[f'Tapa {position} photo']; path = f'2025/tapas/{photo}'
          existing_tapa = one_or_none(select(base, headers, 'tapas', {'select':'id','establishment_id':'eq.'+establishment['id'],'name_es':'eq.'+spanish}), f'tapa {spanish}')
          save(base, headers, 'tapas', {'establishment_id':establishment['id'],'name_en':None,'name_es':spanish,'description_es':venue[f'Tapa {position} description'],'description_en':venue[f'Tapa {position} description (English)'],'photo_path':path,'is_published':True,'participation_status':'active','festival_number':None,'sort_order':position}, existing_tapa)
          uploaded += upload(base, headers, archive, image_map[photo], path)
          processed_photos += 1
          if processed_photos % 10 == 0 or processed_photos == len(image_map):
            print(f'Processing photos: {processed_photos}/{len(image_map)}', flush=True)
    print(f'Import complete: festival={slug}; establishments=62; tapas=124; uploaded photos={uploaded}; existing photos skipped={124-uploaded}.')
if __name__ == '__main__': main()
