library angular.tools.transformer.expression_generator;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular/core/parser/parser.dart';
import 'package:angular/tools/html_extractor.dart';
import 'package:angular/tools/parser_getter_setter/generator.dart';
import 'package:angular/tools/source_crawler.dart';
import 'package:angular/tools/source_metadata_extractor.dart';
import 'package:angular/tools/transformer/options.dart';
import 'package:angular/tools/transformer/referenced_uris.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';
import 'package:path/path.dart' as path;

/**
 * Transformer which gathers all expressions from the HTML source files and
 * Dart source files of an application and packages them for static evaluation.
 *
 * This will also modify the main Dart source file to import the generated
 * expressions and modify all references to NG_EXPRESSION_MODULE to refer to
 * the generated expressions.
 */
class ExpressionGenerator extends Transformer with ResolverTransformer {
  final TransformOptions options;

  ExpressionGenerator(this.options, Resolvers resolvers) {
    this.resolvers = resolvers;
  }

  Future applyResolver(Transform transform, Resolver resolver) {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    _writeStaticExpressionHeader(asset.id, outputBuffer);

    var sourceMetadataExtractor = new SourceMetadataExtractor();
    var directives =
        sourceMetadataExtractor.gatherDirectiveInfo(null,
        new _LibrarySourceCrawler(resolver.libraries));

    var htmlExtractor = new HtmlExpressionExtractor(directives);
    return _getHtmlSources(transform, resolver)
        .forEach(htmlExtractor.parseHtml)
        .then((_) {
      var module = new Module()
        ..type(Parser, implementedBy: DynamicParser)
        ..type(ParserBackend, implementedBy: DartGetterSetterGen);
      var injector =
          new DynamicInjector(modules: [module], allowImplicitInjection: true);

      injector.get(_ParserGetterSetter).generateParser(
          htmlExtractor.expressions.toList(), outputBuffer);

      var id = transform.primaryInput.id;
      var outputFilename = '${path.url.basenameWithoutExtension(id.path)}'
          '_static_expressions.dart';
      var outputPath = path.url.join(path.url.dirname(id.path), outputFilename);
      var outputId = new AssetId(id.package, outputPath);
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));

      transform.addOutput(asset);
    });
  }

  /**
   * Gets a stream consisting of the contents of all HTML source files to be
   * scoured for expressions.
   */
  Stream<String> _getHtmlSources(Transform transform, Resolver resolver) {
    var id = transform.primaryInput.id;

    var controller = new StreamController<String>();
    var assets = options.htmlFiles
        .map((path) => _uriToAssetId(path, transform))
        .where((id) => id != null)
        .toList();

    // Get all of the contents of templates in @Component(templateUrl:'...')
    gatherReferencedUris(transform, resolver, options,
        templatesOnly: true).then((templates) {
      templates.values.forEach(controller.add);
    }).then((_) {
      // Add any HTML files referencing this Dart file.
      return _findHtmlEntry(transform);
    }).then((htmlRefId) {
      if (htmlRefId != null) {
        assets.add(htmlRefId);
      }
      Future.wait(
        // Add any manually specified HTML files.
        assets.map((id) => transform.readInputAsString(id))
            .map((future) =>
                future.then(controller.add).catchError((e) {
                  transform.logger.warning('Unable to find $id from html_files '
                      'in pubspec.yaml.');
                }))
        ).then((_) {
          controller.close();
        });
    });

    return controller.stream;
  }

  AssetId _uriToAssetId(String uri, Transform transform) {
    if (path.url.isAbsolute(uri)) {
      var parts = path.url.split(uri);
      if (parts[1] == 'packages') {
        var pkgPath = path.url.join('lib', path.url.joinAll(parts.skip(3)));
        return new AssetId(parts[2], pkgPath);
      }
      transform.logger.warning('Cannot cache non-package absolute URIs. $uri');
      return null;
    }
    return new AssetId(transform.primaryInput.id.package, uri);
  }

  /// Finds any HTML files referencing the primary input of the transform.
  Future<AssetId> _findHtmlEntry(Transform transform) {
    var id = transform.primaryInput.id;
    // Magic file generated by HtmlDartReferencesGenerator
    var htmlRefId = new AssetId(id.package, id.path + '.html_reference');

    return transform.readInputAsString(htmlRefId).then((path) {
      return new AssetId(id.package, path);
    }, onError: (e, s) => null); // swallow not-found errors.
  }
}

void _writeStaticExpressionHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  libPath = libPath.replaceAll('-', '_');
  sink.write('''
library ${id.package}.$libPath.generated_expressions;

import 'package:angular/change_detection/change_detection.dart';

''');
}

class _LibrarySourceCrawler implements SourceCrawler {
  final Iterable<LibraryElement> libraries;
  _LibrarySourceCrawler(this.libraries);

  void crawl(String entryPoint, CompilationUnitVisitor visitor) {
    libraries.expand((lib) => lib.units)
        .map((compilationUnitElement) => compilationUnitElement.node)
        .forEach(visitor);
  }
}

class _ParserGetterSetter {
  final Parser parser;
  final ParserBackend backend;
  _ParserGetterSetter(this.parser, this.backend);

  generateParser(List<String> exprs, StringSink sink) {
    exprs.forEach((expr) {
      try {
        parser(expr);
      } catch (e) {
        // Ignore exceptions.
      }
    });

    DartGetterSetterGen backend = this.backend;
    sink.write(generateClosures(backend.properties, backend.calls, backend.symbols));
  }

  String generateClosures(Set<String> properties,
                          Set<String> calls,
                          Set<String> symbols) {
    var getters = new Set.from(properties)..addAll(calls);
    return '''
final Map<String, FieldGetter> getters = ${generateGetterMap(getters)};
final Map<String, FieldSetter> setters = ${generateSetterMap(properties)};
final Map<String, Symbol> symbols = ${generateSymbolMap(symbols)};
''';
  }

  generateGetterMap(Iterable<String> keys) {
    var lines = keys.map((key) => '  r"${key}": (o) => o.$key');
    return '{\n${lines.join(",\n")}\n}';
  }

  generateSetterMap(Iterable<String> keys) {
    var lines = keys.map((key) => '  r"${key}": (o, v) => o.$key = v');
    return '{\n${lines.join(",\n")}\n}';
  }

  generateSymbolMap(Set<String> symbols) {
    var lines = symbols.map((key) => '  r"${key}": #$key');
    return '{\n${lines.join(",\n")}\n}';
  }
}

