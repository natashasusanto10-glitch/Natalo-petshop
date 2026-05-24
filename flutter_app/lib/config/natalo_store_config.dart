class NataloStoreConfig {
  NataloStoreConfig._();

  static const name = 'Natalo Petshop / Sinar Petstore';
  static const address = 'JLN MT Haryono No 103 B C D';
  static const hours = '09.00 - 17.00 WIB';
  static const mapsUrl = 'https://share.google/NAfEiYygBy9zIMXoU';

  static const whatsappDisplay = '+62 812 8999 7113';
  static const whatsappNumber = '6281289997113';
  static const email = 'natalopetshop@gmail.com';

  static Uri whatsappUri(
      {String message = 'Halo Natalo, saya butuh bantuan tentang...'}) {
    return Uri.https(
      'wa.me',
      '/$whatsappNumber',
      {'text': message},
    );
  }
}
