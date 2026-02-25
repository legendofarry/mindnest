const String kOwnerEmail = 'karimiarrison@gmail.com';

bool isOwnerEmail(String? email) {
  return (email ?? '').trim().toLowerCase() == kOwnerEmail;
}
