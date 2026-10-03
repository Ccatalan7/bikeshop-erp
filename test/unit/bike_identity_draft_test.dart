import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_identity_draft.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';

Bike _bike({
  String? brandId = 'brand-trek',
  String? brand = 'Trek',
  String? modelId = 'model-marlin',
  String? model = 'Marlin 5',
  String? color = 'Rojo',
  String? notes,
  double? purchasePrice,
  DateTime? purchaseDate,
  String? serialNumber,
  String? imageUrl,
  List<String> imageUrls = const [],
}) =>
    Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brandId: brandId,
      brand: brand,
      modelId: modelId,
      model: model,
      year: 2021,
      color: color,
      notes: notes,
      purchasePrice: purchasePrice,
      purchaseDate: purchaseDate,
      serialNumber: serialNumber,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      bikeType: BikeType.mountainHardtail,
      wheelSize: '29"',
      updatedAt: DateTime.utc(2026, 10, 2, 12),
    );

const _giant = BikeCatalogPick(id: 'brand-giant', name: 'Giant');
const _trek = BikeCatalogPick(id: 'brand-trek', name: 'Trek');

void main() {
  test('opens without changes and builds the bike as it was', () {
    final bike = _bike();
    final draft = BikeIdentityDraft.fromBike(bike);
    expect(draft.hasChanges, isFalse);
    expect(draft.brand, _trek);
    expect(draft.model,
        const BikeCatalogPick(id: 'model-marlin', name: 'Marlin 5'));
    final built = draft.build();
    expect(built.clearCatalogLinks, isEmpty);
    expect(built.bike.toJson(), bike.toJson());
  });

  test('another brand drops the model; the original brand brings it back', () {
    final draft = BikeIdentityDraft.fromBike(_bike());
    draft.setBrand(_giant);
    expect(draft.model, isNull);
    expect(draft.changedFields,
        {BikeIdentityField.brand, BikeIdentityField.model});

    final built = draft.build();
    expect(built.bike.brandId, 'brand-giant');
    expect(built.bike.brand, 'Giant');
    expect(built.clearCatalogLinks, {'model_id'});
    // Sin la clave el servidor conservaría el modelo de Trek con la marca
    // Giant y rechazaría el guardado.
    final payload = BikeshopService.bikeAggregatePayload(
      built.bike,
      clearCatalogLinks: built.clearCatalogLinks,
    );
    expect(payload.containsKey('model_id'), isTrue);
    expect(payload['model_id'], isNull);
    expect(payload['model'], '');

    draft.setBrand(_trek);
    expect(draft.hasChanges, isFalse);
    expect(draft.model?.name, 'Marlin 5');
  });

  test('the same catalog brand written differently keeps the model', () {
    final draft = BikeIdentityDraft.fromBike(_bike(brand: 'TREK'));
    draft.setBrand(_trek);
    expect(draft.isChanged(BikeIdentityField.brand), isTrue);
    expect(draft.isChanged(BikeIdentityField.model), isFalse);
    expect(draft.build().clearCatalogLinks, isEmpty);
  });

  test('undoing the brand also undoes the model it dropped', () {
    final draft = BikeIdentityDraft.fromBike(_bike());
    draft.setBrand(_giant);
    draft.setModel(const BikeCatalogPick(id: 'model-talon', name: 'Talon 2'));
    draft.revert(BikeIdentityField.model);
    expect(draft.hasChanges, isFalse);
    expect(draft.brand, _trek);
  });

  test('only what changed is written; text is trimmed', () {
    final draft =
        BikeIdentityDraft.fromBike(_bike(notes: 'Vino con el eje doblado'));
    draft.setText(BikeIdentityField.color, '  Rojo y negro ');
    draft.setText(BikeIdentityField.serialNumber, 'WTU123');
    expect(draft.changedFields,
        {BikeIdentityField.color, BikeIdentityField.serialNumber});
    final bike = draft.build().bike;
    expect(bike.color, 'Rojo y negro');
    expect(bike.serialNumber, 'WTU123');
    expect(bike.notes, 'Vino con el eje doblado');
    expect(bike.brandId, 'brand-trek');
    expect(draft.originalLabel(BikeIdentityField.color), 'Rojo');

    draft.setText(BikeIdentityField.color, '');
    expect(draft.build().bike.color, isNull);
  });

  test('the price keeps Chilean thousands and saves as a number', () {
    final draft = BikeIdentityDraft.fromBike(_bike(purchasePrice: 450000));
    expect(draft.text(BikeIdentityField.purchasePrice), '450.000');
    draft.setText(BikeIdentityField.purchasePrice, '450.000');
    expect(draft.hasChanges, isFalse);
    draft.setText(BikeIdentityField.purchasePrice, '1290000');
    expect(draft.text(BikeIdentityField.purchasePrice), '1.290.000');
    expect(draft.build().bike.purchasePrice, 1290000);
    expect(draft.label(BikeIdentityField.purchasePrice), r'$ 1.290.000');
  });

  test('a year that is not a year and a warranty before the purchase block',
      () {
    final draft = BikeIdentityDraft.fromBike(_bike());
    draft.setText(BikeIdentityField.year, '21');
    expect(draft.blockingMessage, contains('cuatro cifras'));
    draft.setText(BikeIdentityField.year, '2019');
    expect(draft.blockingMessage, isNull);
    expect(draft.build().bike.year, 2019);

    draft.setDate(BikeIdentityField.purchaseDate, DateTime(2024, 3, 10, 18));
    draft.setDate(BikeIdentityField.warrantyUntil, DateTime(2023, 3, 10));
    expect(draft.blockingMessage, contains('garantía'));
    draft.setDate(BikeIdentityField.warrantyUntil, DateTime(2026, 3, 10));
    expect(draft.blockingMessage, isNull);
    final json = draft.build().bike.toJson();
    expect(json['purchase_date'], startsWith('2024-03-10'));
    expect(draft.label(BikeIdentityField.purchaseDate), '10 mar 2024');
  });

  test('photos: the cover first, removed ones leave, uploaded ones join', () {
    final draft = BikeIdentityDraft.fromBike(_bike(
      imageUrl: 'https://x/cover.jpg',
      imageUrls: const ['https://x/cover.jpg', 'https://x/side.jpg'],
    ));
    expect(draft.photos, ['https://x/cover.jpg', 'https://x/side.jpg']);
    draft.removePhoto('https://x/cover.jpg');
    final photo = BikeNewPhoto(bytes: Uint8List(4), name: 'frente.png');
    draft.addPhoto(photo);
    expect(draft.isChanged(BikeIdentityField.photos), isTrue);
    // Lo que no se subió no va.
    expect(draft.build().bike.imageUrls, ['https://x/side.jpg']);

    draft.markPhotoUploaded(photo, 'https://x/new.png');
    final bike = draft.build().bike;
    expect(bike.imageUrls, ['https://x/side.jpg', 'https://x/new.png']);
    expect(bike.imageUrl, 'https://x/side.jpg');

    draft.revert(BikeIdentityField.photos);
    expect(draft.isChanged(BikeIdentityField.photos), isFalse);
  });

  test('rebase keeps the mechanic changes over the newer bike', () {
    final draft = BikeIdentityDraft.fromBike(_bike());
    draft.setText(BikeIdentityField.color, 'Azul');
    final fresh = _bike(serialNumber: 'Puesto por otro', color: 'Verde');
    final next = draft.rebasedOn(fresh);
    expect(next.text(BikeIdentityField.color), 'Azul');
    expect(next.originalLabel(BikeIdentityField.color), 'Verde');
    expect(next.text(BikeIdentityField.serialNumber), 'Puesto por otro');
    expect(next.changedFields, {BikeIdentityField.color});
  });

  test('rebase never puts a model on another brand', () {
    // Aquí se cambió sólo el modelo; otro guardó la bici como Giant.
    final onlyModel = BikeIdentityDraft.fromBike(_bike())
      ..setModel(const BikeCatalogPick(id: 'model-fathom', name: 'Fathom'));
    final giant = _bike(
        brandId: 'brand-giant',
        brand: 'Giant',
        modelId: 'model-talon',
        model: 'Talon 2');
    final kept = onlyModel.rebasedOn(giant);
    expect(kept.brand, _giant);
    expect(
        kept.model, const BikeCatalogPick(id: 'model-talon', name: 'Talon 2'));
    expect(kept.droppedOnRebase, {BikeIdentityField.model});
    expect(kept.hasChanges, isFalse);

    // Aquí se cambió la marca (y el modelo quedó vacío); otro le puso un
    // modelo a la Trek: la marca nueva lleva su modelo, no el de la Trek.
    final noModel =
        BikeIdentityDraft.fromBike(_bike(modelId: null, model: null))
          ..setBrand(_giant);
    final next = noModel.rebasedOn(_bike());
    expect(next.brand, _giant);
    expect(next.model, isNull);
    expect(next.droppedOnRebase, isEmpty);
    expect(next.build().clearCatalogLinks, {'model_id'});
  });

  test('the image extension falls back to jpg', () {
    expect(bikeImageExtension('Foto.PNG'), '.png');
    expect(bikeImageExtension('sin_extension'), '.jpg');
    expect(bikeImageExtension('doc.pdf'), '.jpg');
  });
}
