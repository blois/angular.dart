library angular.tools.transformer.metadata_generator;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular/tools/transformer/options.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:di/transformer/refactor.dart';
import 'package:path/path.dart' as path;

import 'metadata_extractor.dart';

const String _generatedMetadataFilename = 'generated_metadata.dart';

class MetadataGenerator extends ResolverTransformer {
  final TransformOptions options;

  MetadataGenerator(this.options, Resolvers resolvers) {
    this.resolvers = resolvers;
  }

  Future<bool> isPrimary(Asset input) => new Future.value(
      options.isDartEntry(input.id));

  void applyResolver(Transform transform, Resolver resolver) {
    var asset = transform.primaryInput;
    var extractor = new AnnotationExtractor(transform.logger, resolver);

    var outputBuffer = new StringBuffer();
    _writeHeader(asset.id, outputBuffer);

    var annotatedTypes = resolver.libraries
        .where((lib) => !lib.isInSdk)
        .expand((lib) => lib.units)
        .expand((unit) => unit.types)
        .map(extractor.extractAnnotations)
        .where((annotations) => annotations != null).toList();

    var libs = annotatedTypes.expand((type) => type.referencedLibraries)
        .toSet();

    var importPrefixes = <LibraryElement, String>{};
    var index = 0;
    for (var lib in libs) {
      if (lib.isDartCore) {
        importPrefixes[lib] = '';
        continue;
      }

      var prefix = 'import_${index++}';
      var url = resolver.getImportUri(lib);
      outputBuffer.write('import \'$url\' as $prefix;\n');
      importPrefixes[lib] = '$prefix.';
    }

    _writePreamble(outputBuffer);

    _writeClassPreamble(outputBuffer);
    for (var type in annotatedTypes) {
      type.writeClassAnnotations(
          outputBuffer, transform.logger, resolver, importPrefixes);
    }
    _writeClassEpilogue(outputBuffer);

    _writeMemberPreamble(outputBuffer);
    for (var type in annotatedTypes) {
      type.writeMemberAnnotations(
          outputBuffer, transform.logger, resolver, importPrefixes);
    }
    _writeMemberEpilogue(outputBuffer);

    var outputId =
          new AssetId(asset.id.package, 'lib/$_generatedMetadataFilename');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));

    transformIdentifiers(transform, resolver,
        identifier: 'angular.auto_modules.defaultMetadataModule',
        replacement: 'metadataModule',
        importPrefix: 'generated_metadata',
        importUrl: _generatedMetadataFilename);
  }
}

void _writeHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  sink.write('''
library ${id.package}.$libPath.generated_metadata;

import 'package:angular/angular.dart' show AttrFieldAnnotation, FieldMetadataExtractor, MetadataExtractor;
import 'package:di/di.dart' show Module;

''');
}

void _writePreamble(StringSink sink) {
  sink.write('''
Module get metadataModule => new Module()
    ..value(MetadataExtractor, new _StaticMetadataExtractor())
    ..value(FieldMetadataExtractor, new _StaticFieldMetadataExtractor());

class _StaticMetadataExtractor implements MetadataExtractor {
  Iterable call(Type type) {
    var annotations = _classAnnotations[type];
    if (annotations != null) {
      return annotations;
    }
    return [];
  }
}

class _StaticFieldMetadataExtractor implements FieldMetadataExtractor {
  Map<String, AttrFieldAnnotation> call(Type type) {
    var annotations = _memberAnnotations[type];
    if (annotations != null) {
      return annotations;
    }
    return {};
  }
}

''');
}

void _writeClassPreamble(StringSink sink) {
  sink.write('''
final Map<Type, Object> _classAnnotations = {
''');
}

void _writeClassEpilogue(StringSink sink) {
  sink.write('''
};
''');
}

void _writeMemberPreamble(StringSink sink) {
  sink.write('''

final Map<Type, Map<String, AttrFieldAnnotation>> _memberAnnotations = {
''');
}

void _writeMemberEpilogue(StringSink sink) {
  sink.write('''
};
''');
}

void _writeFooter(StringSink sink) {
  sink.write('''
};
''');
}
