# Expected vars:
# files : a list of files to replace (parametrize variables
# path : path where save temporal files
BEGIN{
  FS = "[\t ]*=[\t ]*"
}

# Special value __path__ this will be replaced by path
$2 == "__path__" {
  $2 = path
}

{
    if ( !($1 in processed)) {
      processed[$1] = "Y"
      if ( $1 ~ /^\$curl\$/) {
        # Format expected $curl$var.name=filename$url.
        # Example: $curl$file.avro=ebms_sourceevents.avsc$http://avro-schema-repo/api/v1/avro/physname/ebms_sourceevents.avsc/noversion/schema
        split($1, a, "\\$")
        varName = a[3]

        split($2, a, "\\$")
        fileName = a[1]
        url = a[2]
        outputFileName = path "/" fileName
        print "curl \"" url "\" -o \"" outputFileName "\""
        print "sed -i \"s@\\${" varName "}@" outputFileName "@g\" " files
      } else {
        # Format expected var.name=value
        # Example log4j.loglevel=INFO
        print "sed -i \"s@\\${" $1 "}@" $2 "@g\" " files
      }
    }
}
