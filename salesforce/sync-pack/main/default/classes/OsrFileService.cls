@RestResource(urlMapping='/osr/v1/files')
global with sharing class OsrFileService {
    global class FileScope {
        public String linkedEntityObject;
        public Long maxBytes;
    }
    global class FilesRequest {
        public String cursor;
        public List<FileScope> scopes;
    }
    global class FilePayload {
        public String contentVersionId;
        public String contentDocumentId;
        public String title;
        public String path;
        public String hash;
        public Long size;
        public String mimeType;
        public String downloadUrl;
    }
    global class FilesResponse {
        public String cursor;
        public List<FilePayload> files;
    }

    @HttpPost
    global static void manifest() {
        writeJson(buildResponse());
    }

    public static FilesResponse buildResponse() {
        FilesRequest req = (FilesRequest) JSON.deserialize(
            RestContext.request.requestBody.toString(),
            FilesRequest.class
        );
        FilesResponse res = new FilesResponse();
        res.cursor = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        res.files = new List<FilePayload>();

        // MVP: latest ContentVersions the user can see (scoped further by LinkedEntity later)
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Checksum, FileType
            FROM ContentVersion
            WHERE IsLatest = TRUE
            ORDER BY SystemModstamp DESC
            LIMIT 50
        ];
        for (ContentVersion cv : versions) {
            if (req != null && req.scopes != null && !req.scopes.isEmpty()) {
                Long maxBytes = req.scopes[0].maxBytes;
                if (maxBytes != null && cv.ContentSize != null && cv.ContentSize > maxBytes) {
                    continue;
                }
            }
            FilePayload f = new FilePayload();
            f.contentVersionId = cv.Id;
            f.contentDocumentId = cv.ContentDocumentId;
            f.title = cv.Title;
            f.size = cv.ContentSize;
            f.hash = cv.Checksum;
            f.mimeType = cv.FileType;
            f.path = '/services/data/v61.0/sobjects/ContentVersion/' + cv.Id + '/VersionData';
            f.downloadUrl = f.path;
            res.files.add(f);
        }
        return res;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }
}
