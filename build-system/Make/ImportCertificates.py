import os
import sys
import argparse

from BuildEnvironment import run_executable_with_output


def _keychain_path():
    runner_temp = os.environ.get('RUNNER_TEMP')
    if runner_temp:
        return os.path.join(runner_temp, 'ninepeaksgram.keychain-db')
    return os.path.expanduser('~/Library/Keychains/ninepeaksgram.keychain-db')


def import_certificates(certificatesPath):
    if not os.path.exists(certificatesPath):
        print('{} does not exist'.format(certificatesPath))
        sys.exit(1)

    keychain_path = _keychain_path()
    keychain_password = 'secret'
    p12_password = os.environ.get('TELEGRAM_FAKE_P12_PASSWORD', '')

    run_executable_with_output('security', arguments=['delete-keychain', keychain_path], check_result=False)

    run_executable_with_output('security', arguments=[
        'create-keychain',
        '-p',
        keychain_password,
        keychain_path
    ], check_result=True)

    # Keep the keychain unlocked for the whole Bazel compile + sign.
    run_executable_with_output('security', arguments=[
        'set-keychain-settings', '-lut', '21600', keychain_path
    ], check_result=True)
    run_executable_with_output('security', arguments=[
        'unlock-keychain', '-p', keychain_password, keychain_path
    ], check_result=True)
    run_executable_with_output('security', arguments=[
        'default-keychain', '-s', keychain_path
    ], check_result=True)

    existing_keychains = run_executable_with_output(
        'security', arguments=['list-keychains', '-d', 'user']
    )
    search_list = [keychain_path]
    for line in existing_keychains.splitlines():
        path = line.strip().strip('"')
        if path and path not in search_list:
            search_list.append(path)
    run_executable_with_output('security', arguments=[
        'list-keychains', '-d', 'user', '-s'
    ] + search_list, check_result=True)

    for file_name in os.listdir(certificatesPath):
        file_path = certificatesPath + '/' + file_name
        if file_path.endswith('.p12'):
            run_executable_with_output('security', arguments=[
                'import',
                file_path,
                '-k',
                keychain_path,
                '-P',
                p12_password,
                '-A',
                '-T',
                '/usr/bin/codesign',
                '-T',
                '/usr/bin/security'
            ], check_result=True)
        elif file_path.endswith('.cer'):
            run_executable_with_output('security', arguments=[
                'import',
                file_path,
                '-k',
                keychain_path,
                '-A',
                '-T',
                '/usr/bin/codesign',
                '-T',
                '/usr/bin/security'
            ], check_result=False)

    apple_wwdr = 'build-system/AppleWWDRCAG3.cer'
    if os.path.exists(apple_wwdr):
        run_executable_with_output('security', arguments=[
            'import',
            apple_wwdr,
            '-k',
            keychain_path,
            '-A',
            '-T',
            '/usr/bin/codesign',
            '-T',
            '/usr/bin/security'
        ], check_result=False)

    run_executable_with_output('security', arguments=[
        'set-key-partition-list',
        '-S',
        'apple-tool:,apple:,codesign:',
        '-s',
        '-k',
        keychain_password,
        keychain_path
    ], check_result=True)

    identities = run_executable_with_output('security', arguments=[
        'find-identity', '-v', '-p', 'codesigning', keychain_path
    ], check_result=False)
    print(identities)
    if '0 valid identities found' in identities or 'valid identities found' not in identities:
        print('Warning: no codesigning identities yet after import; trust setup may still make them visible')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(prog='build')

    parser.add_argument(
        '--path',
        required=True,
        help='Path to certificates.'
    )

    if len(sys.argv) < 2:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()

    import_certificates(args.path)
