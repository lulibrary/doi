/**
 * Created by albincla on 05/05/15.
 */
function setupLiveValidation() {
    var creatorName = new LiveValidation('creatorName');
    creatorName.add( Validate.Presence );

    var title = new LiveValidation('title');
    title.add( Validate.Presence );

    var publisher = new LiveValidation('publisher');
    publisher.add( Validate.Presence );

    var publicationYear = new LiveValidation('publicationYear');
    publicationYear.add( Validate.Presence );
    publicationYear.add( Validate.Numericality, { onlyInteger: true } );
    publicationYear.add( Validate.Length, { is: 4 } );
}

setupLiveValidation();