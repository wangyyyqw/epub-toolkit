# Bundled OpenCC dictionaries

The four gzip files contain OpenCC dictionary text, attributed in their headers
to BYVoid/OpenCC and licensed under Apache-2.0 (see LICENSE).

This snapshot updates dictionary content as well as compressing the resources.
It is not a byte-identical compression of the previous repository dictionaries.
No upstream commit identifier was recorded with the supplied snapshot; do not
claim that it corresponds to a particular OpenCC release.

Entry counts: STPhrases 49,951; STCharacters 4,110; TSCharacters 4,270;
TSPhrases 481. Tests cover loading, identity phrases and longest-match behavior.
