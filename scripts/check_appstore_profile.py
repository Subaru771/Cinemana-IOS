#!/usr/bin/env python3
"""Preflight a locally decoded App Store profile. Never print signing material.
This checks metadata, not CMS trust, revocation or the eventual app signature.
"""
from datetime import datetime, timezone
import plistlib
import sys


def validate(profile, team, now=None):
    now = now or datetime.now(timezone.utc)
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime) or expiry.replace(tzinfo=timezone.utc) <= now:
        raise ValueError('Provisioning profile is expired or has no expiry')
    entitlements = profile.get('Entitlements', {})
    if profile.get('TeamIdentifier') != [team] or entitlements.get('com.apple.developer.team-identifier') != team:
        raise ValueError('Provisioning team mismatch')
    if entitlements.get('application-identifier') != team + '.app.cinemana.mobile.ios':
        raise ValueError('Provisioning application identifier mismatch')
    if (profile.get('ProvisionedDevices') is not None or profile.get('ProvisionsAllDevices') or
            entitlements.get('get-task-allow') is not False or entitlements.get('beta-reports-active') is not True):
        raise ValueError('Expected an App Store distribution profile, not development, Ad Hoc or enterprise')
    if not profile.get('DeveloperCertificates'):
        raise ValueError('Profile has no signing certificate')
    for field in ('UUID', 'Name'):
        value = profile.get(field)
        if not isinstance(value, str) or not value or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError('Invalid provisioning profile metadata')


if __name__ == '__main__':
    try:
        with open(sys.argv[1], 'rb') as source:
            validate(plistlib.load(source), sys.argv[2])
    except (ValueError, KeyError, TypeError, OSError, plistlib.InvalidFileException):
        raise SystemExit('App Store profile preflight failed; check expiry, team, bundle ID and distribution type locally.')
    print('App Store profile metadata preflight passed; signing and Apple acceptance still required.')
